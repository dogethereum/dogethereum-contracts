import hre from "hardhat";
import { assert } from "chai";
import type { Contract, BigNumber, BigNumberish } from "ethers";

import { deployFixture } from "../deploy";

import {
  checkDogeTokenInvariant,
  base58ToBytes20,
  isolateEachTest,
  isolateTests,
} from "./utils";

interface Utxo {
  txHash: string;
  value: BigNumber;
  index: number;
}

function createUtxo(txHash: string, value: BigNumberish, index = 1): Utxo {
  if (!hre.ethers.BigNumber.isBigNumber(value)) {
    value = hre.ethers.BigNumber.from(value);
  }
  return {
    txHash,
    value,
    index,
  };
}

describe("testDogeTokenDoUnlock", function () {
  let dogeToken: Contract;
  let accounts: string[];

  let dogeAddress: string;
  let operatorPublicKeyHash: string;
  let operatorEthAddress: string;

  let OPERATOR_UNLOCK_FEE: BigNumber;
  let DOGETHEREUM_FEE_FRACTION: BigNumber;
  let DOGE_TX_FEE_RATE: BigNumber;
  let DOGE_TX_INPUT_SIZE: BigNumber;
  let DOGE_TX_OUTPUT_SIZE: BigNumber;
  let DOGE_TX_FIXED_SIZE: BigNumber;
  let DOGE_DUST: BigNumber;

  isolateTests();
  isolateEachTest();

  before(async function () {
    const dogethereum = await deployFixture(hre);
    dogeToken = dogethereum.dogeToken;

    accounts = (await hre.ethers.getSigners()).map((signer) => signer.address);
    operatorEthAddress = accounts[3];
    operatorPublicKeyHash = `0x4d905b4b815d483cdfabcd292c6f86509d0fad82`;
    dogeAddress = base58ToBytes20("DHx8ZyJJuiFM5xAHFypfz1k6bd2X85xNMy");

    await dogeToken.addOperatorSimple(
      operatorPublicKeyHash,
      operatorEthAddress
    );

    OPERATOR_UNLOCK_FEE = await dogeToken.callStatic.OPERATOR_UNLOCK_FEE();
    DOGETHEREUM_FEE_FRACTION =
      await dogeToken.callStatic.DOGETHEREUM_FEE_FRACTION();
    DOGE_TX_FEE_RATE = await dogeToken.callStatic.DOGE_TX_FEE_RATE();
    DOGE_TX_INPUT_SIZE = await dogeToken.callStatic.DOGE_TX_INPUT_SIZE();
    DOGE_TX_OUTPUT_SIZE = await dogeToken.callStatic.DOGE_TX_OUTPUT_SIZE();
    DOGE_TX_FIXED_SIZE = await dogeToken.callStatic.DOGE_TX_FIXED_SIZE();
    DOGE_DUST = await dogeToken.callStatic.DOGE_DUST();
  });

  async function setupUtxos(utxos: Utxo[], account: string) {
    const utxosValue = sumUtxoValue(utxos);

    await dogeToken.assign(account, utxosValue);
    for (const utxo of utxos) {
      await dogeToken.addUtxo(
        operatorPublicKeyHash,
        utxo.value,
        utxo.txHash,
        1
      );
    }

    await checkDogeTokenInvariant(dogeToken);

    return {
      utxosValue,
    };
  }

  it("doUnlock single utxo", async function () {
    const userBalance = hre.ethers.BigNumber.from(2000000000);
    const utxoValue = userBalance;
    const utxos = [createUtxo("0x01", utxoValue)];
    await setupUtxos(utxos, accounts[0]);

    let balance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(
      balance.toString(),
      userBalance.toString(),
      `DogeToken's ${accounts[0]} balance is not the expected one`
    );
    const utxo = await dogeToken.getUtxo(operatorPublicKeyHash, 0);
    assert.equal(
      utxo.value.toString(),
      utxoValue.toString(),
      `Utxo value is not the expected one`
    );

    const unlockValue = hre.ethers.BigNumber.from(1000000000);
    await dogeToken.doUnlock(dogeAddress, unlockValue, operatorPublicKeyHash);

    // Note that this assumes a single input was selected.
    // Which is reasonable since we added only one utxo.
    const dogeTxSize = DOGE_TX_FIXED_SIZE.add(DOGE_TX_INPUT_SIZE).add(
      DOGE_TX_OUTPUT_SIZE.mul(2)
    );
    const dogeTxFee = DOGE_TX_FEE_RATE.mul(dogeTxSize);
    const operatorFee = unlockValue
      .mul(OPERATOR_UNLOCK_FEE)
      .div(DOGETHEREUM_FEE_FRACTION);

    const valueToUser = unlockValue.sub(dogeTxFee).sub(operatorFee);
    const operatorChange = utxoValue.sub(dogeTxFee).sub(valueToUser);

    await checkDogeTokenInvariant(dogeToken);

    const unlock = await dogeToken.getUnlock(0);
    unlockSanityCheck(unlock, accounts[0], dogeAddress, operatorPublicKeyHash);
    assert.equal(
      unlock.valueToUser.toString(),
      valueToUser.toString(),
      `Unlock value is not the expected one`
    );
    assert.equal(
      unlock.operatorChange.toString(),
      operatorChange.toString(),
      `Unlock operator change is not the expected one`
    );
    assert.lengthOf(
      unlock.selectedUtxos,
      1,
      `Unlock selectedUtxos should have one utxo`
    );
    assert.equal(
      unlock.selectedUtxos[0],
      0,
      `Unlock selectedUtxos is not the expected one`
    );

    balance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(
      balance.toString(),
      userBalance.sub(unlockValue).toString(),
      `DogeToken's user balance after unlock is not the expected one`
    );

    const operatorTokenBalance: BigNumber = await dogeToken.balanceOf(
      operatorEthAddress
    );
    assert.equal(
      operatorTokenBalance.toString(),
      operatorFee.toString(),
      `DogeToken's operator balance after unlock is not the expected one`
    );

    const unlockIdx = await dogeToken.unlockIdx();
    assert.equal(unlockIdx, 1, "unlockIdx is not the expected one");

    const operator = await dogeToken.operators(operatorPublicKeyHash);
    assert.equal(
      operator.dogeAvailableBalance.toString(),
      0,
      "operator dogeAvailableBalance is not the expected one"
    );
    assert.equal(
      operator.dogePendingBalance.toString(),
      operatorChange.toString(),
      "operator dogePendingBalance is not the expected one"
    );
    assert.equal(
      operator.nextUnspentUtxoIndex,
      1,
      "operator nextUnspentUtxoIndex is not the expected one"
    );
  });

  it("doUnlock with multiple utxos", async function () {
    const utxos = [
      createUtxo("0x01", 400000000),
      createUtxo("0x02", 200000000),
      createUtxo("0x03", 600000000),
      createUtxo("0x04", 800000000),
      createUtxo("0x05", 900000000),
      createUtxo("0x06", 900000000),
      createUtxo("0x07", 900000000),
      createUtxo("0x08", 900000000),
    ];
    const { utxosValue } = await setupUtxos(utxos, accounts[0]);

    const firstUnlockValue = hre.ethers.BigNumber.from(1000000000);
    const firstExpectedSelectedUtxos = [0, 1, 2];
    const firstUtxos = firstExpectedSelectedUtxos.map((index) => utxos[index]);
    const firstUtxosValue = sumUtxoValue(firstUtxos);
    const firstOperatorFee = firstUnlockValue
      .mul(OPERATOR_UNLOCK_FEE)
      .div(DOGETHEREUM_FEE_FRACTION);
    const firstDogeTxSize = DOGE_TX_FIXED_SIZE.add(
      DOGE_TX_INPUT_SIZE.mul(firstExpectedSelectedUtxos.length)
    ).add(DOGE_TX_OUTPUT_SIZE.mul(2));
    const firstDogeTxFee = DOGE_TX_FEE_RATE.mul(firstDogeTxSize);
    const firstValueToUser = firstUnlockValue
      .sub(firstDogeTxFee)
      .sub(firstOperatorFee);
    const firstOperatorChange = firstUtxosValue
      .sub(firstDogeTxFee)
      .sub(firstValueToUser);

    // Unlock Request 1
    await dogeToken.doUnlock(
      dogeAddress,
      firstUnlockValue,
      operatorPublicKeyHash
    );
    let totalUnlocks = await dogeToken.unlockIdx();
    assert.equal(totalUnlocks, 1, "totalUnlocks is not the expected one");

    let unlock = await dogeToken.getUnlock(0);
    unlockSanityCheck(unlock, accounts[0], dogeAddress, operatorPublicKeyHash);
    assert.equal(
      unlock.valueToUser.toString(),
      firstValueToUser.toString(),
      `Unlock value is not the expected one`
    );
    assert.equal(
      unlock.operatorChange.toString(),
      firstOperatorChange.toString(),
      `Unlock operator change is not the expected one`
    );
    assert.sameOrderedMembers(
      unlock.selectedUtxos,
      firstExpectedSelectedUtxos,
      `Unlock selectedUtxos are not the expected ones`
    );

    let userBalance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(
      userBalance.toString(),
      utxosValue.sub(firstUnlockValue).toString(),
      `DogeToken user balance after unlock is not the expected one`
    );

    let operatorTokenBalance = await dogeToken.balanceOf(operatorEthAddress);
    assert.equal(
      operatorTokenBalance.toString(),
      firstOperatorFee.toString(),
      `DogeToken's operator balance after unlock is not the expected one`
    );

    let operator = await dogeToken.operators(operatorPublicKeyHash);
    assert.equal(
      operator.dogeAvailableBalance.toString(),
      utxosValue.sub(firstUtxosValue).toString(),
      "operator dogeAvailableBalance is not the expected one"
    );
    assert.equal(
      operator.dogePendingBalance.toString(),
      firstOperatorChange.toString(),
      "operator dogePendingBalance is not the expected one"
    );
    assert.equal(
      operator.nextUnspentUtxoIndex,
      3,
      "operator nextUnspentUtxoIndex is not the expected one"
    );

    await checkDogeTokenInvariant(dogeToken);

    const secondUnlockValue = hre.ethers.BigNumber.from(1500000000);
    const secondExpectedSelectedUtxos = [3, 4];
    const secondUtxos = secondExpectedSelectedUtxos.map(
      (index) => utxos[index]
    );
    const secondUtxosValue = sumUtxoValue(secondUtxos);
    const secondOperatorFee = secondUnlockValue
      .mul(OPERATOR_UNLOCK_FEE)
      .div(DOGETHEREUM_FEE_FRACTION);
    const secondDogeTxSize = DOGE_TX_FIXED_SIZE.add(
      DOGE_TX_INPUT_SIZE.mul(secondExpectedSelectedUtxos.length)
    ).add(DOGE_TX_OUTPUT_SIZE.mul(2));
    const secondDogeTxFee = DOGE_TX_FEE_RATE.mul(secondDogeTxSize);
    const secondValueToUser = secondUnlockValue
      .sub(secondDogeTxFee)
      .sub(secondOperatorFee);
    const secondOperatorChange = secondUtxosValue
      .sub(secondDogeTxFee)
      .sub(secondValueToUser);

    // Unlock Request 2
    await dogeToken.doUnlock(
      dogeAddress,
      secondUnlockValue,
      operatorPublicKeyHash
    );
    totalUnlocks = await dogeToken.unlockIdx();
    assert.equal(totalUnlocks, 2, "totalUnlocks is not the expected one");

    unlock = await dogeToken.getUnlock(1);
    unlockSanityCheck(unlock, accounts[0], dogeAddress, operatorPublicKeyHash);
    assert.equal(
      unlock.valueToUser.toString(),
      secondValueToUser.toString(),
      `Unlock value is not the expected one`
    );
    assert.equal(
      unlock.operatorChange.toString(),
      secondOperatorChange.toString(),
      `Unlock operator fee is not the expected one`
    );
    assert.sameOrderedMembers(
      unlock.selectedUtxos,
      secondExpectedSelectedUtxos,
      `Unlock selectedUtxos are not the expected ones`
    );

    userBalance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(
      userBalance,
      utxosValue.sub(firstUnlockValue).sub(secondUnlockValue).toString(),
      `DogeToken user balance after unlock is not the expected one`
    );

    operatorTokenBalance = await dogeToken.balanceOf(operatorEthAddress);
    assert.equal(
      operatorTokenBalance.toString(),
      firstOperatorFee.add(secondOperatorFee).toString(),
      `DogeToken operator balance after unlock is not the expected one`
    );

    operator = await dogeToken.operators(operatorPublicKeyHash);
    assert.equal(
      operator.dogeAvailableBalance.toString(),
      utxosValue.sub(firstUtxosValue).sub(secondUtxosValue).toString(),
      "operator dogeAvailableBalance is not the expected one"
    );
    assert.equal(
      operator.dogePendingBalance.toString(),
      firstOperatorChange.add(secondOperatorChange).toString(),
      "operator dogePendingBalance is not the expected one"
    );
    assert.equal(
      operator.nextUnspentUtxoIndex,
      5,
      "operator nextUnspentUtxoIndex is not the expected one"
    );

    await checkDogeTokenInvariant(dogeToken);
  });

  it("doUnlock avoids dust outputs in operator change", async function () {
    const utxo1Value = hre.ethers.BigNumber.from(2_000_000_000);
    const utxo2Value = hre.ethers.BigNumber.from(100_000_000);
    const userBalance = utxo1Value.add(utxo2Value);
    const utxos = [
      createUtxo("0x01", utxo1Value),
      createUtxo("0x02", utxo2Value),
    ];
    await setupUtxos(utxos, accounts[0]);

    // This ensures the operator change is dust.
    const unlockValue = utxo1Value.add(19_900_000);

    await dogeToken.doUnlock(dogeAddress, unlockValue, operatorPublicKeyHash);

    // Note that this assumes a single input was selected.
    // Which is reasonable since we added only one utxo.
    const dogeTxSize =
      DOGE_TX_FIXED_SIZE.add(DOGE_TX_INPUT_SIZE).add(DOGE_TX_OUTPUT_SIZE);
    // Tx fee without dust
    const dogeTxFee = DOGE_TX_FEE_RATE.mul(dogeTxSize);
    const operatorFee = unlockValue
      .mul(OPERATOR_UNLOCK_FEE)
      .div(DOGETHEREUM_FEE_FRACTION);

    const valueToUserWithDust = unlockValue.sub(dogeTxFee).sub(operatorFee);
    const dust = utxo1Value.sub(dogeTxFee).sub(valueToUserWithDust);
    const valueToUser = valueToUserWithDust.sub(dust);
    const operatorChange = hre.ethers.BigNumber.from(0);

    await checkDogeTokenInvariant(dogeToken);

    const unlock = await dogeToken.getUnlock(0);

    unlockSanityCheck(unlock, accounts[0], dogeAddress, operatorPublicKeyHash);
    assert.equal(
      unlock.valueToUser.toString(),
      valueToUser.toString(),
      `Unlock value is not the expected one`
    );
    assert.equal(
      unlock.operatorChange.toString(),
      operatorChange.toString(),
      `Unlock operator change is not the expected one`
    );
    assert.lengthOf(
      unlock.selectedUtxos,
      1,
      `Unlock selectedUtxos should have one utxo`
    );
    assert.equal(
      unlock.selectedUtxos[0],
      0,
      `Unlock selectedUtxos is not the expected one`
    );

    const balance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(
      balance.toString(),
      userBalance.sub(unlockValue).toString(),
      `DogeToken's user balance after unlock is not the expected one`
    );

    const operatorTokenBalance: BigNumber = await dogeToken.balanceOf(
      operatorEthAddress
    );
    assert.equal(
      operatorTokenBalance.toString(),
      operatorFee.sub(dust).toString(),
      `DogeToken's operator balance after unlock is not the expected one`
    );

    const unlockIdx = await dogeToken.unlockIdx();
    assert.equal(unlockIdx, 1, "unlockIdx is not the expected one");

    const operator = await dogeToken.operators(operatorPublicKeyHash);
    assert.equal(
      operator.dogeAvailableBalance.toString(),
      utxo2Value.toString(),
      "operator dogeAvailableBalance is not the expected one"
    );
    assert.equal(
      operator.dogePendingBalance.toString(),
      operatorChange.toString(),
      "operator dogePendingBalance is not the expected one"
    );
    assert.equal(
      operator.nextUnspentUtxoIndex,
      1,
      "operator nextUnspentUtxoIndex is not the expected one"
    );
  });
});

function sumUtxoValue(utxos: Array<{ value: BigNumber }>): BigNumber {
  return utxos.reduce((subtotal, utxo) => {
    return subtotal.add(utxo.value);
  }, hre.ethers.BigNumber.from(0));
}

function unlockSanityCheck(
  unlock: {
    from: string;
    dogeAddress: string;
    operatorPublicKeyHash: string;
    completed: boolean;
  },
  sender: string,
  senderDogeAddress: string,
  operatorPublicKeyHash: string
) {
  assert.equal(unlock.from, sender, `Unlock from is not the expected one`);
  assert.equal(
    unlock.dogeAddress,
    senderDogeAddress,
    `Unlock doge address is not the expected one`
  );
  assert.equal(
    unlock.operatorPublicKeyHash,
    operatorPublicKeyHash,
    `Unlock operatorPublicKeyHash is not the expected one`
  );
  assert.isFalse(unlock.completed, `Unlock should be marked as incomplete`);
}

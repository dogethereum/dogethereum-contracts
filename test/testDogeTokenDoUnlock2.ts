import hre from "hardhat";
import { assert } from "chai";
import type { Contract, ContractTransaction } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { deployFixture } from "../deploy";

import { base58ToBytes20, isolateTests } from "./utils";

describe("testDogeTokenDoUnlock2", function () {
  let dogeToken: Contract;
  let accounts: string[];

  isolateTests();

  before(async function () {
    const dogethereum = await deployFixture(hre);
    dogeToken = dogethereum.dogeToken;

    accounts = (await hre.ethers.getSigners()).map((signer) => signer.address);
  });

  it("doUnlock whith multiple utxos", async () => {
    const operatorPublicKeyHash = `0x4d905b4b815d483cdfabcd292c6f86509d0fad82`;
    const operatorEthAddress = accounts[3];
    await dogeToken.addOperatorSimple(
      operatorPublicKeyHash,
      operatorEthAddress
    );

    await dogeToken.assign(accounts[0], 5600000000);
    let balance = await dogeToken.balanceOf(accounts[0]);

    await dogeToken.addUtxo(operatorPublicKeyHash, 400000000, 1, 1);
    await dogeToken.addUtxo(operatorPublicKeyHash, 200000000, 2, 1);
    await dogeToken.addUtxo(operatorPublicKeyHash, 600000000, 3, 1);
    await dogeToken.addUtxo(operatorPublicKeyHash, 800000000, 4, 1);
    await dogeToken.addUtxo(operatorPublicKeyHash, 900000000, 4, 1);
    await dogeToken.addUtxo(operatorPublicKeyHash, 900000000, 4, 1);
    await dogeToken.addUtxo(operatorPublicKeyHash, 900000000, 4, 1);
    await dogeToken.addUtxo(operatorPublicKeyHash, 900000000, 4, 1);

    const dogeAddress = base58ToBytes20("DHx8ZyJJuiFM5xAHFypfz1k6bd2X85xNMy");

    //address from, bytes20 dogeAddress, uint value, uint operatorFee,
    //uint timestamp, uint32[] memory selectedUtxos, uint dogeTxFee, bytes20 operatorPublicKeyHash

    // Unlock Request 1
    await dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash);
    let unlockPendingInvestorProof = await dogeToken.getUnlockPendingInvestorProof(
      0
    );
    assert.sameOrderedMembers(
      unlockPendingInvestorProof.selectedUtxos,
      [0, 1, 2],
      `Unlock selectedUtxos are not the expected ones`
    );
    assert.equal(
      unlockPendingInvestorProof.operatorFee.toNumber(),
      10000000,
      `Unlock operator fee is not the expected one`
    );
    assert.equal(
      unlockPendingInvestorProof.dogeTxFee.toNumber(),
      350000000,
      `Unlock dogeTxFee is not the expected one`
    );
    balance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(
      balance,
      4600000000,
      `DogeToken's ${accounts[0]} balance after unlock is not the expected one`
    );
    let operatorTokenBalance = await dogeToken.balanceOf(operatorEthAddress);
    assert.equal(
      operatorTokenBalance.toNumber(),
      10000000,
      `DogeToken's operator balance after unlock is not the expected one`
    );
    let unlockIdx = await dogeToken.unlockIdx();
    assert.equal(unlockIdx, 1, "unlockIdx is not the expected one");
    let operator = await dogeToken.operators(operatorPublicKeyHash);
    assert.equal(
      operator.dogeAvailableBalance.toString(),
      4400000000,
      "operator dogeAvailableBalance is not the expected one"
    );
    assert.equal(
      operator.dogePendingBalance.toString(),
      210000000,
      "operator dogePendingBalance is not the expected one"
    );
    assert.equal(
      operator.nextUnspentUtxoIndex,
      3,
      "operator nextUnspentUtxoIndex is not the expected one"
    );

    // Unlock Request 2
    await dogeToken.doUnlock(dogeAddress, 1500000000, operatorPublicKeyHash);
    unlockPendingInvestorProof = await dogeToken.getUnlockPendingInvestorProof(
      1
    );
    assert.sameOrderedMembers(
      unlockPendingInvestorProof.selectedUtxos,
      [3, 4],
      `Unlock selectedUtxos are not the expected ones`
    );
    assert.equal(
      unlockPendingInvestorProof.operatorFee.toNumber(),
      15000000,
      `Unlock operator fee is not the expected one`
    );
    assert.equal(
      unlockPendingInvestorProof.dogeTxFee.toNumber(),
      250000000,
      `Unlock dogeTxFee is not the expected one`
    );
    balance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(
      balance,
      3100000000,
      `DogeToken's ${accounts[0]} balance after unlock is not the expected one`
    );
    operatorTokenBalance = await dogeToken.balanceOf(operatorEthAddress);
    assert.equal(
      operatorTokenBalance.toNumber(),
      25000000,
      `DogeToken's operator balance after unlock is not the expected one`
    );
    unlockIdx = await dogeToken.unlockIdx();
    assert.equal(unlockIdx, 2, "unlockIdx is not the expected one");
    operator = await dogeToken.operators(operatorPublicKeyHash);
    assert.equal(
      operator.dogeAvailableBalance.toString(),
      2700000000,
      "operator dogeAvailableBalance is not the expected one"
    );
    assert.equal(
      operator.dogePendingBalance.toString(),
      425000000,
      "operator dogePendingBalance is not the expected one"
    );
    assert.equal(
      operator.nextUnspentUtxoIndex,
      5,
      "operator nextUnspentUtxoIndex is not the expected one"
    );
  });
});

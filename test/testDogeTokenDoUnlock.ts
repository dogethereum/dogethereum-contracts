import hre from "hardhat";
import { assert } from "chai";
import type { Contract, ContractTransaction } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { deployFixture } from "../deploy";

import { base58ToBytes20, isolateTests } from "./utils";

describe("testDogeTokenDoUnlock", function () {
  let dogeToken: Contract;
  let accounts: string[];

  isolateTests();

  before(async function () {
    const dogethereum = await deployFixture(hre);
    dogeToken = dogethereum.dogeToken;

    accounts = (await hre.ethers.getSigners()).map((signer) => signer.address);
  });

  it("doUnlock does not fail", async () => {
    const operatorPublicKeyHash = `0x4d905b4b815d483cdfabcd292c6f86509d0fad82`;
    const operatorEthAddress = accounts[3];
    await dogeToken.addOperatorSimple(
      operatorPublicKeyHash,
      operatorEthAddress
    );

    await dogeToken.assign(accounts[0], 2000000000);
    let balance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(
      balance,
      2000000000,
      `DogeToken's ${accounts[0]} balance is not the expected one`
    );

    await dogeToken.addUtxo(operatorPublicKeyHash, 2000000000, 1, 10);
    const utxo = await dogeToken.getUtxo(operatorPublicKeyHash, 0);
    assert.equal(
      utxo.value.toNumber(),
      2000000000,
      `Utxo value is not the expected one`
    );

    const dogeAddress = base58ToBytes20("DHx8ZyJJuiFM5xAHFypfz1k6bd2X85xNMy");
    await dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash);

    const unlockPendingInvestorProof = await dogeToken.getUnlockPendingInvestorProof(
      0
    );
    assert.equal(
      unlockPendingInvestorProof.from,
      accounts[0],
      `Unlock from is not the expected one`
    );
    assert.equal(
      unlockPendingInvestorProof.dogeAddress,
      dogeAddress,
      `Unlock doge address is not the expected one`
    );
    assert.equal(
      unlockPendingInvestorProof.value.toNumber(),
      1000000000,
      `Unlock value is not the expected one`
    );
    assert.equal(
      unlockPendingInvestorProof.operatorFee.toNumber(),
      10000000,
      `Unlock operator fee is not the expected one`
    );
    assert.equal(
      unlockPendingInvestorProof.selectedUtxos[0],
      0,
      `Unlock selectedUtxos is not the expected one`
    );
    assert.equal(
      unlockPendingInvestorProof.dogeTxFee.toNumber(),
      150000000,
      `Unlock fee is not the expected one`
    );
    assert.equal(
      unlockPendingInvestorProof.operatorPublicKeyHash,
      operatorPublicKeyHash,
      `Unlock operatorPublicKeyHash is not the expected one`
    );

    balance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(
      balance.toNumber(),
      1000000000,
      `DogeToken's user balance after unlock is not the expected one`
    );

    const operatorTokenBalance = await dogeToken.balanceOf(operatorEthAddress);
    assert.equal(
      operatorTokenBalance.toNumber(),
      10000000,
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
      1010000000,
      "operator dogePendingBalance is not the expected one"
    );
    assert.equal(
      operator.nextUnspentUtxoIndex,
      1,
      "operator nextUnspentUtxoIndex is not the expected one"
    );
  });
});

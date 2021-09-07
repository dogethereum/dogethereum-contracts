import { assert } from "chai";
import hre from "hardhat";
import type { Contract } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { deployFixture, deployToken } from "../deploy";

import {
  buildDogeTransaction,
  dogeAddressFromKeyPair,
  dogeKeyPairFromWIF,
  expectFailure,
  isolateEachTest,
  isolateTests,
  publicKeyHashFromKeyPair,
} from "./utils";

describe("testDogeTokenProcessTransaction", function () {
  let signers: SignerWithAddress[];
  let trustedRelayerContract: string;
  let operatorEthAddress: string;
  let superblockSubmitterAddress: string;
  const collateralRatio = 2;

  const userEthAddress = "0x30d90d1dbf03aa127d58e6af83ca1da9e748c98d";
  const value = 905853205327;

  const keypairs = [
    "QSRUX7i1WVzFW6vx3i4Qj8iPPQ1tRcuPanMun8BKf8ySc8LsUuKx",
    "QULAK58teBn1Xi4eGo4fKea5oQDPMK4vcnmnivqzgvCPagsWHiyf",
  ].map(dogeKeyPairFromWIF);

  const operatorAddress = dogeAddressFromKeyPair(keypairs[0]);

  const lockTx = buildDogeTransaction({
    signer: keypairs[1],
    inputs: [
      {
        txId:
          "edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67",
        index: 0,
      },
    ],
    outputs: [
      { type: "payment", address: operatorAddress, value },
      {
        type: "data embed",
        value: 0,
        data: Buffer.from(userEthAddress.slice(2), "hex"),
      },
    ],
  });
  const operatorPublicKeyHash = publicKeyHashFromKeyPair(keypairs[0]);
  const txData = `0x${lockTx.toHex()}`;
  const txHash = `0x${lockTx.getId()}`;

  let dogeToken: Contract;

  isolateTests();
  isolateEachTest();

  before(async function () {
    signers = await hre.ethers.getSigners();
    const { dogeToken: fixtureToken } = await deployFixture(hre);
    // Tell DogeToken to trust signers[0] as if it were the relayer contract
    trustedRelayerContract = signers[0].address;
    operatorEthAddress = signers[3].address;
    superblockSubmitterAddress = signers[4].address;

    const dogeUsdPriceOracle = await fixtureToken.callStatic.dogeUsdOracle();
    const ethUsdPriceOracle = await fixtureToken.callStatic.ethUsdOracle();

    const dogeTokenSystem = await deployToken(
      hre,
      "DogeTokenForTests",
      signers[0],
      dogeUsdPriceOracle,
      ethUsdPriceOracle,
      trustedRelayerContract,
      collateralRatio
    );
    dogeToken = dogeTokenSystem.dogeToken.contract;
  });

  it("processTransaction success", async () => {
    await dogeToken.addOperatorSimple(
      operatorPublicKeyHash,
      operatorEthAddress
    );

    const superblockSubmitterAddress = signers[4].address;
    await dogeToken.processLockTransaction(
      txData,
      txHash,
      operatorPublicKeyHash,
      superblockSubmitterAddress
    );

    const operatorFee = Math.floor(value / 100);
    const superblockSubmitterFee = Math.floor(value / 100);
    const userValue = value - operatorFee - superblockSubmitterFee;

    const balance = await dogeToken.balanceOf(userEthAddress);
    assert.equal(
      balance,
      userValue,
      `DogeToken's ${userEthAddress} balance is not the expected one`
    );
    const operatorTokenBalance = await dogeToken.balanceOf(operatorEthAddress);
    assert.equal(
      operatorTokenBalance,
      operatorFee,
      `DogeToken's operator balance is not the expected one`
    );
    const superblockSubmitterTokenBalance = await dogeToken.balanceOf(
      superblockSubmitterAddress
    );
    assert.equal(
      superblockSubmitterTokenBalance,
      superblockSubmitterFee,
      `DogeToken's superblock submitter balance is not the expected one`
    );

    const utxo = await dogeToken.getUtxo(operatorPublicKeyHash, 0);
    assert.equal(utxo.value, value, `Utxo's value is not the expected one`);
    assert.equal(
      utxo.txHash.toHexString(),
      txHash,
      `Utxo's value is not the expected one`
    );
    assert.equal(utxo.index, 0, `Utxo's index is not the expected one`);

    const operator = await dogeToken.operators(operatorPublicKeyHash);
    assert.equal(
      operator.dogeAvailableBalance,
      value,
      "operator dogeAvailableBalance is not the expected one"
    );
  });

  it("processTransaction fail - operator not created", async () => {
    await expectFailure(
      () => {
        return dogeToken.processLockTransaction(
          txData,
          txHash,
          operatorPublicKeyHash,
          superblockSubmitterAddress
        );
      },
      (error) =>
        assert.include(
          error.message,
          "Operator is not registered",
          "Expected operator to not be registered."
        )
    );
  });

  it("processTransaction fail - tx already processed", async () => {
    await dogeToken.addOperatorSimple(
      operatorPublicKeyHash,
      operatorEthAddress
    );
    await dogeToken.processLockTransaction(
      txData,
      txHash,
      operatorPublicKeyHash,
      superblockSubmitterAddress
    );

    await expectFailure(
      () =>
        dogeToken.processLockTransaction(
          txData,
          txHash,
          operatorPublicKeyHash,
          superblockSubmitterAddress
        ),
      (error) =>
        assert.include(
          error.message,
          "Transaction already processed.",
          "Expected transaction to be already processed."
        )
    );
  });
});

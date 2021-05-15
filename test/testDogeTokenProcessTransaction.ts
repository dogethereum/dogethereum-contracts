import { assert } from "chai";
import hre from "hardhat";
import type { Contract } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { deployFixture, deployContract } from "../deploy";

import {
  buildDogeTransaction,
  dogeAddressFromKeyPair,
  dogeKeyPairFromWIF,
  isolateTests,
  publicKeyHashFromKeyPair,
} from "./utils";

describe("testDogeTokenProcessTransaction", function () {
  let signers: SignerWithAddress[];
  let snapshot: any;
  const trustedDogeEthPriceOracle =
    "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
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

  before(async function () {
    signers = await hre.ethers.getSigners();
    // Tell DogeToken to trust signers[0] as if it were the relayer contract
    trustedRelayerContract = signers[0].address;
    operatorEthAddress = signers[3].address;
    superblockSubmitterAddress = signers[4].address;
  });

  beforeEach(async function () {
    const { setLibrary } = await deployFixture(hre);
    dogeToken = await deployContract(
      "DogeTokenForTests",
      [trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio],
      hre,
      { signer: signers[0], libraries: { Set: setLibrary.address } }
    );
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
    assert.equal(utxo[0], value, `Utxo's value is not the expected one`);
    assert.equal(
      utxo[1].toHexString(),
      txHash,
      `Utxo's value is not the expected one`
    );
    assert.equal(utxo[2], 0, `Utxo's index is not the expected one`);

    const operator = await dogeToken.operators(operatorPublicKeyHash);
    assert.equal(
      operator[1],
      value,
      "operator dogeAvailableBalance is not the expected one"
    );
  });

  it("processTransaction fail - operator not created", async () => {
    const processTransactionTxResponse = await dogeToken.processLockTransaction(
      txData,
      txHash,
      operatorPublicKeyHash,
      superblockSubmitterAddress
    );
    const processTransactionTxReceipt = await processTransactionTxResponse.wait();
    assert.equal(
      60060,
      processTransactionTxReceipt.events[0].args.err,
      "Expected ERR_PROCESS_OPERATOR_NOT_CREATED error"
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

    const processTransactionTxResponse = await dogeToken.processLockTransaction(
      txData,
      txHash,
      operatorPublicKeyHash,
      superblockSubmitterAddress
    );
    const processTransactionTxReceipt = await processTransactionTxResponse.wait();
    assert.equal(
      60070,
      processTransactionTxReceipt.events[0].args.err,
      "Expected ERR_PROCESS_TX_ALREADY_PROCESSED error"
    );
  });
});

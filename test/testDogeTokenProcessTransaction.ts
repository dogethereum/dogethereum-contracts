import { assert } from "chai";
import hre from "hardhat";
import type { Contract, ContractTransaction } from "ethers";
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

describe("Token transaction processing", function () {
  let signers: SignerWithAddress[];
  let trustedRelayerContract: string;
  let operatorEthAddress: string;
  let superblockSubmitterAddress: string;
  const collateralRatio = 2;

  let userEthSigner: SignerWithAddress;
  const value = 905853205327;
  const change = 458205327;

  const keypairs = [
    "QSRUX7i1WVzFW6vx3i4Qj8iPPQ1tRcuPanMun8BKf8ySc8LsUuKx",
    "QULAK58teBn1Xi4eGo4fKea5oQDPMK4vcnmnivqzgvCPagsWHiyf",
  ].map(dogeKeyPairFromWIF);
  const operatorKeypair = keypairs[0];
  const userKeypair = keypairs[1];

  const operatorDogeAddress = dogeAddressFromKeyPair(operatorKeypair);
  const operatorPublicKeyHash = publicKeyHashFromKeyPair(operatorKeypair);

  const userAddress = dogeAddressFromKeyPair(userKeypair);
  const userPublicKeyHash = publicKeyHashFromKeyPair(userKeypair);

  const utxoRef = {
    txId: "edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67",
    index: 0,
  };

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
    userEthSigner = signers[5];

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

  describe("processLockTransaction", function () {
    let lockTx;
    let lockTxData: string;
    let lockTxHash: string;

    before(function () {
      lockTx = buildDogeTransaction({
        signer: userKeypair,
        inputs: [utxoRef],
        outputs: [
          { type: "payment", address: operatorDogeAddress, value },
          {
            type: "data embed",
            value: 0,
            data: Buffer.from(userEthSigner.address.slice(2), "hex"),
          },
        ],
      });
      lockTxData = `0x${lockTx.toHex()}`;
      lockTxHash = `0x${lockTx.getId()}`;
    });

    it("processLockTransaction success", async () => {
      await dogeToken.addOperatorSimple(
        operatorPublicKeyHash,
        operatorEthAddress
      );

      const superblockSubmitterAddress = signers[4].address;
      await dogeToken.processLockTransaction(
        lockTxData,
        lockTxHash,
        operatorPublicKeyHash,
        superblockSubmitterAddress
      );

      const operatorFee = Math.floor(value / 100);
      const superblockSubmitterFee = Math.floor(value / 100);
      const userValue = value - operatorFee - superblockSubmitterFee;

      const balance = await dogeToken.balanceOf(userEthSigner.address);
      assert.equal(
        balance,
        userValue,
        `DogeToken's ${userEthSigner.address} balance is not the expected one`
      );
      const operatorTokenBalance = await dogeToken.balanceOf(
        operatorEthAddress
      );
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
        lockTxHash,
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

    it("processLockTransaction fail - operator not created", async () => {
      await expectFailure(
        () => {
          return dogeToken.processLockTransaction(
            lockTxData,
            lockTxHash,
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

    it("processLockTransaction fail - tx already processed", async () => {
      await dogeToken.addOperatorSimple(
        operatorPublicKeyHash,
        operatorEthAddress
      );
      await dogeToken.processLockTransaction(
        lockTxData,
        lockTxHash,
        operatorPublicKeyHash,
        superblockSubmitterAddress
      );

      await expectFailure(
        () =>
          dogeToken.processLockTransaction(
            lockTxData,
            lockTxHash,
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

  describe("processUnlockTransaction", function () {
    const operatorFee = Math.floor(value * 0.01);
    const dogeTxFeeOneInput = 150000000;

    const unlockTx = buildDogeTransaction({
      signer: operatorKeypair,
      inputs: [utxoRef],
      outputs: [
        {
          type: "payment",
          address: userAddress,
          value: value - operatorFee - dogeTxFeeOneInput,
        },
      ],
    });

    const unlockTxWithChange = buildDogeTransaction({
      signer: operatorKeypair,
      inputs: [utxoRef],
      outputs: [
        {
          type: "payment",
          address: userAddress,
          value: value - operatorFee - dogeTxFeeOneInput,
        },
        { type: "payment", address: operatorDogeAddress, value: change },
      ],
    });
    const unlockRequests = [
      {
        name: "unlock without change",
        utxoValue: value - operatorFee,
        requestValue: value,
        data: `0x${unlockTx.toHex()}`,
        hash: `0x${unlockTx.getId()}`,
      },
      {
        name: "unlock with change",
        utxoValue: value - operatorFee + change,
        requestValue: value,
        data: `0x${unlockTxWithChange.toHex()}`,
        hash: `0x${unlockTxWithChange.getId()}`,
      },
    ];

    let userDogeToken: Contract;

    before(function () {
      userDogeToken = dogeToken.connect(userEthSigner);
    });

    for (const unlockRequest of unlockRequests) {
      it(`valid ${unlockRequest.name} output`, async function () {
        await dogeToken.addOperatorSimple(
          operatorPublicKeyHash,
          operatorEthAddress
        );
        await dogeToken.addUtxo(
          operatorPublicKeyHash,
          unlockRequest.utxoValue,
          `0x${utxoRef.txId}`,
          utxoRef.index
        );
        await dogeToken.assign(userEthSigner.address, value);
        await userDogeToken.doUnlock(
          userPublicKeyHash,
          unlockRequest.requestValue,
          operatorPublicKeyHash
        );

        const tx: ContractTransaction = await dogeToken.processUnlockTransaction(
          unlockRequest.data,
          unlockRequest.hash,
          operatorPublicKeyHash,
          superblockSubmitterAddress
        );
        const receipt = await tx.wait();
        const errorEvents = receipt.events!.filter(({ event }) => {
          event === "ErrorDogeToken";
        });
        assert.lengthOf(
          errorEvents,
          0,
          "Errors occurred while processing unlock."
        );
      });
    }
  });

  describe("processReportOperatorFreeUtxoSpend", function () {
    const operatorFee = Math.floor(value * 0.01);
    const dogeTxFeeOneInput = 150000000;

    const rogueTx = buildDogeTransaction({
      signer: operatorKeypair,
      inputs: [utxoRef],
      outputs: [
        {
          type: "payment",
          address: userAddress,
          value: value - operatorFee - dogeTxFeeOneInput,
        },
        { type: "payment", address: operatorDogeAddress, value: change },
      ],
    });
    const dogeTx = {
      utxoValue: value - operatorFee + change,
      rogueInputIndex: 0,
      data: `0x${rogueTx.toHex()}`,
      hash: `0x${rogueTx.getId()}`,
    };

    let userDogeToken: Contract;

    before(function () {
      userDogeToken = dogeToken.connect(userEthSigner);
    });

    it(`valid report of free utxo`, async function () {
      await dogeToken.addOperatorSimple(
        operatorPublicKeyHash,
        operatorEthAddress
      );
      await dogeToken.addUtxo(
        operatorPublicKeyHash,
        dogeTx.utxoValue,
        `0x${utxoRef.txId}`,
        utxoRef.index
      );

      const tx: ContractTransaction = await dogeToken.processReportOperatorFreeUtxoSpend(
        dogeTx.data,
        dogeTx.hash,
        operatorPublicKeyHash,
        utxoRef.index,
        dogeTx.rogueInputIndex
      );
      const receipt = await tx.wait();
      const liquidateEvents = receipt.events!.filter(({ event }) => {
        return event === "OperatorLiquidated";
      });
      assert.lengthOf(liquidateEvents, 1, "Operator wasn't liquidated.");
    });

    it(`fail report of free utxo after it's been reserved`, async function () {
      await dogeToken.addOperatorSimple(
        operatorPublicKeyHash,
        operatorEthAddress
      );
      await dogeToken.addUtxo(
        operatorPublicKeyHash,
        dogeTx.utxoValue,
        `0x${utxoRef.txId}`,
        utxoRef.index
      );
      await dogeToken.assign(userEthSigner.address, value);
      await userDogeToken.doUnlock(
        userPublicKeyHash,
        value,
        operatorPublicKeyHash
      );

      await expectFailure(
        () =>
          dogeToken.processReportOperatorFreeUtxoSpend(
            dogeTx.data,
            dogeTx.hash,
            operatorPublicKeyHash,
            utxoRef.index,
            dogeTx.rogueInputIndex
          ),
        (error) => {
          assert.include(
            error.message,
            "The UTXO is already reserved or spent"
          );
        }
      );
    });
  });
});

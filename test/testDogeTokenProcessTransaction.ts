import { assert } from "chai";
import hre from "hardhat";
import type { Contract, ContractTransaction } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { deployFixture, deployToken, TokenOptions } from "../deploy";

import {
  buildDogeTransaction,
  checkDogeTokenInvariant,
  dogeAddressFromKeyPair,
  dogeKeyPairFromWIF,
  DogeTxDescriptor,
  expectFailure,
  isolateEachTest,
  isolateTests,
  publicKeyHashFromKeyPair,
} from "./utils";

interface UnlockTest {
  /**
   * Name of the test
   */
  name: string;
  /**
   * Value of the utxo used
   */
  utxoValue: number;
  /**
   * Value requested to unlock
   */
  requestValue: number;
  /**
   * Raw signed Dogecoin tx
   */
  data: string;
  /**
   * Dogecoin tx hash
   */
  hash: string;
}

describe("Token transaction processing", function () {
  let signers: SignerWithAddress[];
  let trustedRelayerContract: string;
  let operatorEthAddress: string;
  let superblockSubmitterAddress: string;
  const tokenOptions: TokenOptions = {
    lockCollateralRatio: "2000",
    liquidationThresholdCollateralRatio: "1500",
    unlockEthereumTimeGracePeriod: 4 * 60 * 60,
    unlockSuperblocksHeightGracePeriod: 4,
  };

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
    const { dogeToken: fixtureToken, superblocks } = await deployFixture(hre);
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
      superblocks.address,
      tokenOptions
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

    it("processLockTransaction success", async function () {
      await dogeToken.addOperatorSimple(
        operatorPublicKeyHash,
        operatorEthAddress
      );

      await checkDogeTokenInvariant(dogeToken);

      const superblockSubmitterAddress = signers[4].address;
      await dogeToken.processLockTransaction(
        lockTxData,
        lockTxHash,
        operatorPublicKeyHash,
        superblockSubmitterAddress
      );

      await checkDogeTokenInvariant(dogeToken);

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

    it("processLockTransaction fail - operator not created", async function () {
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

    it("processLockTransaction fail - tx already processed", async function () {
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
    const dogeTxFeeRate = 1_000;
    const dogeTxSizeOneInputOneOutput = 148 + 34 + 10;
    const dogeTxSizeOneInputTwoOutputs = 148 + 34 * 2 + 10;
    const dogeTxFeeOneInputOneOutput =
      dogeTxFeeRate * dogeTxSizeOneInputOneOutput;
    const dogeTxFeeOneInputTwoOutputs =
      dogeTxFeeRate * dogeTxSizeOneInputTwoOutputs;

    const unlockTx = buildDogeTransaction({
      signer: operatorKeypair,
      inputs: [utxoRef],
      outputs: [
        {
          type: "payment",
          address: userAddress,
          value: value - operatorFee - dogeTxFeeOneInputOneOutput,
        },
      ],
    });

    const unlockTxWithChangeDescriptor: DogeTxDescriptor = {
      signer: operatorKeypair,
      inputs: [utxoRef],
      outputs: [
        {
          type: "payment",
          address: userAddress,
          value: value - operatorFee - dogeTxFeeOneInputTwoOutputs,
        },
        { type: "payment", address: operatorDogeAddress, value: change },
      ],
    };
    const unlockTxWithChange = buildDogeTransaction(
      unlockTxWithChangeDescriptor
    );
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
        const unlockIndex = await prepareUnlock(unlockRequest);

        const tx: ContractTransaction =
          await dogeToken.processUnlockTransaction(
            unlockRequest.data,
            unlockRequest.hash,
            operatorPublicKeyHash,
            unlockIndex
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

    it(`should fail when missing the change output`, async function () {
      const unlockRequest = { ...unlockRequests[0] };
      assert.equal(
        unlockRequest.requestValue - operatorFee,
        unlockRequest.utxoValue,
        "The unlock request this test is based on needs to have no change output associated with it"
      );
      unlockRequest.utxoValue *= 3;
      unlockRequest.requestValue *= 2;
      const unlockIndex = await prepareUnlock(unlockRequest);

      await expectFailure(
        () =>
          dogeToken.processUnlockTransaction(
            unlockRequest.data,
            unlockRequest.hash,
            operatorPublicKeyHash,
            unlockIndex
          ),
        (error) => {
          assert.include(
            error.message,
            "transaction doesn't have enough outputs"
          );
        }
      );
    });

    it(`should fail when the user output value is wrong`, async function () {
      const unlockRequest = { ...unlockRequests[1] };
      unlockRequest.utxoValue *= 3;
      unlockRequest.requestValue *= 2;
      const unlockIndex = await prepareUnlock(unlockRequest);

      await expectFailure(
        () =>
          dogeToken.processUnlockTransaction(
            unlockRequest.data,
            unlockRequest.hash,
            operatorPublicKeyHash,
            unlockIndex
          ),
        (error) => {
          assert.include(
            error.message,
            "Wrong amount of dogecoins sent to user"
          );
        }
      );
    });

    it(`should fail when the user output address is wrong`, async function () {
      const unlockRequest = { ...unlockRequests[1] };
      const wrongAddressDescriptor: DogeTxDescriptor = {
        signer: operatorKeypair,
        inputs: [utxoRef],
        outputs: [
          {
            type: "payment",
            address: operatorDogeAddress,
            value: value - operatorFee - dogeTxFeeOneInputTwoOutputs,
          },
          { type: "payment", address: operatorDogeAddress, value: change },
        ],
      };
      const wrongAddressTx = buildDogeTransaction(wrongAddressDescriptor);
      unlockRequest.data = `0x${wrongAddressTx.toHex()}`;
      unlockRequest.hash = `0x${wrongAddressTx.getId()}`;
      const unlockIndex = await prepareUnlock(unlockRequest);

      await expectFailure(
        () =>
          dogeToken.processUnlockTransaction(
            unlockRequest.data,
            unlockRequest.hash,
            operatorPublicKeyHash,
            unlockIndex
          ),
        (error) => {
          assert.include(
            error.message,
            "Wrong dogecoin public key hash for user"
          );
        }
      );
    });

    it(`should fail when the operator output address is wrong`, async function () {
      const unlockRequest = { ...unlockRequests[1] };
      const wrongAddressDescriptor: DogeTxDescriptor = {
        signer: operatorKeypair,
        inputs: [utxoRef],
        outputs: [
          {
            type: "payment",
            address: userAddress,
            value: value - operatorFee - dogeTxFeeOneInputTwoOutputs,
          },
          { type: "payment", address: userAddress, value: change },
        ],
      };
      const wrongAddressTx = buildDogeTransaction(wrongAddressDescriptor);
      unlockRequest.data = `0x${wrongAddressTx.toHex()}`;
      unlockRequest.hash = `0x${wrongAddressTx.getId()}`;
      const unlockIndex = await prepareUnlock(unlockRequest);

      await expectFailure(
        () =>
          dogeToken.processUnlockTransaction(
            unlockRequest.data,
            unlockRequest.hash,
            operatorPublicKeyHash,
            unlockIndex
          ),
        (error) => {
          assert.include(
            error.message,
            "Wrong dogecoin public key hash for operator"
          );
        }
      );
    });

    async function prepareUnlock(unlockRequest: UnlockTest) {
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
      await dogeToken.assign(userEthSigner.address, unlockRequest.requestValue);

      const unlockIndex = await dogeToken.callStatic.unlockIdx();
      await userDogeToken.doUnlock(
        userPublicKeyHash,
        unlockRequest.requestValue,
        operatorPublicKeyHash
      );
      return unlockIndex;
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

      const tx: ContractTransaction =
        await dogeToken.processReportOperatorFreeUtxoSpend(
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

  describe("processReportOperatorUtxoBadSpend", function () {
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

      const tx: ContractTransaction =
        await dogeToken.processReportOperatorFreeUtxoSpend(
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
  });
});

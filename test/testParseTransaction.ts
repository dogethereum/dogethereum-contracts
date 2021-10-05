import type { ECPairInterface, Transaction } from "bitcoinjs-lib";
import { assert, expect } from "chai";
import type { Contract } from "ethers";
import hre from "hardhat";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { deployContract } from "../deploy";

import {
  base58ToBytes20,
  buildDogeTransaction,
  dogeAddressFromKeyPair,
  dogeKeyPairFromWIF,
  DogeTxDescriptor,
  expectFailure,
  isolateTests,
  publicKeyHashFromKeyPair,
} from "./utils";

describe("testParseTransaction", () => {
  let dogeMessageLibraryForTests: Contract;
  let signers: SignerWithAddress[];
  let operatorKeyPair: ECPairInterface;
  let userKeyPair: ECPairInterface;
  let operatorDogeAddress: string;
  let userDogeAddress: string;

  isolateTests();

  before(async function () {
    signers = await hre.ethers.getSigners();
    const keys = [
      "QSRUX7i1WVzFW6vx3i4Qj8iPPQ1tRcuPanMun8BKf8ySc8LsUuKx",
      "QULAK58teBn1Xi4eGo4fKea5oQDPMK4vcnmnivqzgvCPagsWHiyf",
    ].map(dogeKeyPairFromWIF);
    operatorKeyPair = keys[0];
    userKeyPair = keys[1];
    operatorDogeAddress = dogeAddressFromKeyPair(operatorKeyPair);
    userDogeAddress = dogeAddressFromKeyPair(userKeyPair);
  });

  beforeEach(async function () {
    const [signer] = signers;
    dogeMessageLibraryForTests = await deployContract(
      "DogeMessageLibraryForTests",
      [],
      hre,
      { signer }
    );
  });

  describe("Parse lock transactions", function () {
    it("Attempt to parse invalid transaction", async function () {
      const destinationEthereumAddress = signers[3].address;
      const decodedDestination = Buffer.from(
        destinationEthereumAddress.slice(2),
        "hex"
      );
      const tx = buildDogeTransaction({
        signer: userKeyPair,
        inputs: [
          {
            txId:
              "edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67",
            index: 0,
          },
        ],
        outputs: [
          {
            type: "payment",
            address: userDogeAddress,
            value: 1000001,
          },
          { type: "data embed", value: 0, data: decodedDestination },
          {
            type: "payment",
            address: operatorDogeAddress,
            value: 1000002,
          },
        ],
      });
      const operatorPublicKeyHash = publicKeyHashFromKeyPair(operatorKeyPair);
      const txData = `0x${tx.toHex()}`;

      await expectFailure(
        () =>
          dogeMessageLibraryForTests.parseLockTransaction(
            txData,
            operatorPublicKeyHash
          ),
        (error) => {
          expect(error).to.be.an.instanceOf(Error);
          expect(error.message)
            .to.be.a("string")
            .and.include(
              "The first tx output does not have a P2PKH output script for an operator."
            );
        }
      );
    });

    it("Attempt to parse transaction without operator output", async function () {
      const tx = buildDogeTransaction({
        signer: userKeyPair,
        inputs: [
          {
            txId:
              "edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67",
            index: 0,
          },
        ],
        outputs: [
          {
            type: "payment",
            address: operatorDogeAddress,
            value: 100000,
          },
        ],
      });
      const operatorPublicKeyHash = publicKeyHashFromKeyPair(operatorKeyPair);
      const txData = `0x${tx.toHex()}`;

      await expectFailure(
        () =>
          dogeMessageLibraryForTests.parseLockTransaction(
            txData,
            operatorPublicKeyHash
          ),
        (error) => {
          expect(error).to.be.an.instanceOf(Error);
          expect(error.message)
            .to.be.a("string")
            .and.include("Lock transactions only have two or three outputs.");
        }
      );
    });

    it("Parse valid lock transaction", async function () {
      const destinationEthereumAddress = signers[3].address;
      const decodedDestination = Buffer.from(
        destinationEthereumAddress.slice(2),
        "hex"
      );
      const lockAmount = 1000002;
      const tx = buildDogeTransaction({
        signer: userKeyPair,
        inputs: [
          {
            txId:
              "edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67",
            index: 0,
          },
        ],
        outputs: [
          {
            type: "payment",
            address: operatorDogeAddress,
            value: lockAmount,
          },
          { type: "data embed", value: 0, data: decodedDestination },
          {
            type: "payment",
            address: operatorDogeAddress,
            value: 1000001,
          },
        ],
      });
      const operatorPublicKeyHash = publicKeyHashFromKeyPair(operatorKeyPair);
      const txData = `0x${tx.toHex()}`;

      const parseResult = await dogeMessageLibraryForTests.parseLockTransaction(
        txData,
        operatorPublicKeyHash
      );
      assert.equal(
        parseResult[0],
        lockAmount,
        "Amount deposited to operator is incorrect"
      );
      assert.equal(
        parseResult[1],
        destinationEthereumAddress,
        "User ethereum address is incorrect"
      );
      assert.equal(
        parseResult[2],
        0,
        "The operator output should be the first one"
      );
    });
  });

  describe("Parse unlock transactions", function () {
    let shortTxDescriptor: DogeTxDescriptor;
    let shortTx: Transaction;
    let shortTxData: string;

    let longTxDescriptor: DogeTxDescriptor;
    let longTx: Transaction;
    let longTxData: string;

    before(function () {
      shortTxDescriptor = {
        signer: operatorKeyPair,
        inputs: [
          {
            txId:
              "edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67",
            index: 3,
          },
          {
            txId:
              "dd418758b611b84c23770219e427df67edbbd164551c8961cf5f7f4b22d7a299",
            index: 1,
          },
          {
            txId:
              "23770219e427df67dd418758b611b84ccf5f7f4b22d7a299edbbd164551c8961",
            index: 4,
          },
        ],
        outputs: [
          {
            type: "payment",
            address: operatorDogeAddress,
            value: 1000002,
          },
          {
            type: "payment",
            address: operatorDogeAddress,
            value: 1000001,
          },
        ],
      };
      shortTx = buildDogeTransaction(shortTxDescriptor);
      shortTxData = `0x${shortTx.toHex()}`;

      longTxDescriptor = {
        signer: operatorKeyPair,
        inputs: [
          {
            txId:
              "edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67",
            index: 3,
          },
          {
            txId:
              "dd418758b611b84c23770219e427df67edbbd164551c8961cf5f7f4b22d7a299",
            index: 1,
          },
          {
            txId:
              "23770219e427df67dd418758b611b84ccf5f7f4b22d7a299edbbd164551c8961",
            index: 4,
          },
        ],
        outputs: [
          {
            type: "payment",
            address: operatorDogeAddress,
            value: 1000002,
          },
          {
            type: "data embed",
            value: 0,
            data: Buffer.from("Arbitrary testing data"),
          },
          {
            type: "payment",
            address: operatorDogeAddress,
            value: 1000001,
          },
        ],
      };
      longTx = buildDogeTransaction(longTxDescriptor);
      longTxData = `0x${longTx.toHex()}`;
    });

    it("Parse valid unlock transaction", async function () {
      const amountOfInputs = 2;
      const amountOfOutputs = 1;
      const {
        outpoints,
        outputs,
      } = await dogeMessageLibraryForTests.parseUnlockTransaction(
        shortTxData,
        amountOfInputs,
        amountOfOutputs
      );

      assert.lengthOf(
        outpoints,
        amountOfInputs,
        "Should parse requested inputs"
      );
      assert.lengthOf(
        outputs,
        amountOfOutputs,
        "Should parse requested outputs"
      );

      for (let i = 0; i < outpoints.length; i++) {
        const outpoint = outpoints[i];
        const input = shortTxDescriptor.inputs[i];
        assert.equal(
          outpoint.txHash.toHexString(),
          `0x${input.txId}`,
          "Unexpected tx hash parsed in input"
        );
        assert.equal(
          outpoint.txIndex,
          input.index,
          "Unexpected tx output index parsed in input"
        );
      }

      for (let i = 0; i < outputs.length; i++) {
        const parsedOutput = outputs[i];
        const output = shortTxDescriptor.outputs[i];
        assert.equal(
          parsedOutput.value.toString(),
          output.value,
          "Unexpected tx value parsed in output"
        );
        if (output.type === "payment") {
          assert.equal(
            parsedOutput.publicKeyHash,
            base58ToBytes20(output.address),
            "Unexpected address parsed in output"
          );
        }
      }
    });

    it("Unlock without enough outputs should revert", async function () {
      const amountOfInputs = 2;
      const amountOfOutputs = 3;
      await expectFailure(
        () =>
          dogeMessageLibraryForTests.parseUnlockTransaction(
            shortTxData,
            amountOfInputs,
            amountOfOutputs
          ),
        (error) => {
          assert.include(
            error.message,
            "transaction doesn't have enough outputs"
          );
        }
      );
    });

    it("Unlock without enough inputs should revert", async function () {
      const amountOfInputs = 4;
      const amountOfOutputs = 2;
      await expectFailure(
        () =>
          dogeMessageLibraryForTests.parseUnlockTransaction(
            shortTxData,
            amountOfInputs,
            amountOfOutputs
          ),
        (error) => {
          assert.include(
            error.message,
            "transaction doesn't have enough inputs"
          );
        }
      );
    });

    it("Unlock with non P2PKH output scripts should revert", async function () {
      const amountOfInputs = 2;
      const amountOfOutputs = 2;
      await expectFailure(
        () =>
          dogeMessageLibraryForTests.parseUnlockTransaction(
            longTxData,
            amountOfInputs,
            amountOfOutputs
          ),
        (error) => {
          assert.include(error.message, "Expected a P2PKH script");
        }
      );
    });
  });
});

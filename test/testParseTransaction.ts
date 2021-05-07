import { assert, expect } from "chai";
import type { Contract } from "ethers";
import hre from "hardhat";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { deployContract } from "../deploy";

import {
  buildDogeTransaction,
  dogeAddressFromKeyPair,
  dogeKeyPairFromWIF,
  isolateTests,
  publicKeyHashFromKeyPair,
} from "./utils";

describe("testParseTransaction", () => {
  let dogeMessageLibraryForTests: Contract;
  let signers: SignerWithAddress[];
  let snapshot: any;
  const keys = [
    "QSRUX7i1WVzFW6vx3i4Qj8iPPQ1tRcuPanMun8BKf8ySc8LsUuKx",
    "QULAK58teBn1Xi4eGo4fKea5oQDPMK4vcnmnivqzgvCPagsWHiyf",
  ].map(dogeKeyPairFromWIF);

  isolateTests();

  before(async () => {
    signers = await hre.ethers.getSigners();
  });

  beforeEach(async () => {
    const [signer] = signers;
    dogeMessageLibraryForTests = await deployContract(
      "DogeMessageLibraryForTests",
      [],
      hre,
      { signer }
    );
  });

  it("Parse simple transation", async () => {
    const tx = buildDogeTransaction({
      signer: keys[1],
      inputs: [
        ["edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67", 0],
      ],
      outputs: [
        [dogeAddressFromKeyPair(keys[1]), 1000001],
        [dogeAddressFromKeyPair(keys[0]), 1000002],
      ],
    });
    const operatorPublicKeyHash = publicKeyHashFromKeyPair(keys[0]);
    const txData = `0x${tx.toHex()}`;
    const txHash = `0x${tx.getId()}`;

    try {
      const parseResult = await dogeMessageLibraryForTests.parseLockTransaction(
        txData,
        operatorPublicKeyHash
      );
    } catch (error) {
      expect(error).to.be.an.instanceOf(Error);
      expect(error.message)
        .to.be.a("string")
        .and.include(
          "The first tx output does not have a P2PKH output script for an operator."
        );
      return;
    }
    assert.fail("The lock transaction is invalid and should be rejected.");
  });
  it("Parse transation without operator output", async () => {
    const tx = buildDogeTransaction({
      signer: keys[1],
      inputs: [
        ["edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67", 0],
      ],
      outputs: [[dogeAddressFromKeyPair(keys[0]), 1000002]],
    });
    const operatorPublicKeyHash = publicKeyHashFromKeyPair(keys[1]);
    const txData = `0x${tx.toHex()}`;
    const txHash = `0x${tx.getId()}`;

    try {
      const parseResult = await dogeMessageLibraryForTests.parseLockTransaction(
        txData,
        operatorPublicKeyHash
      );
    } catch (error) {
      expect(error).to.be.an.instanceOf(Error);
      expect(error.message)
        .to.be.a("string")
        .and.include("Lock transactions only have two or three outputs.");
      return;
    }
    assert.fail("The lock transaction is invalid and should be rejected.");
  });
  it("Parse transaction with OP_RETURN", async () => {
    const operatorKeyPair = keys[0];
    const destinationEthereumAddress = signers[3].address;
    const decodedDestination = Buffer.from(
      destinationEthereumAddress.slice(2),
      "hex"
    );
    const tx = buildDogeTransaction({
      signer: keys[1],
      inputs: [
        ["edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67", 0],
      ],
      outputs: [
        [dogeAddressFromKeyPair(operatorKeyPair), 1000002],
        ["OP_RETURN", 0, decodedDestination],
        [dogeAddressFromKeyPair(keys[1]), 1000001],
      ],
    });
    const operatorPublicKeyHash = publicKeyHashFromKeyPair(operatorKeyPair);
    const txData = `0x${tx.toHex()}`;
    const txHash = `0x${tx.getId()}`;

    const parseResult = await dogeMessageLibraryForTests.parseLockTransaction(
      txData,
      operatorPublicKeyHash
    );
    assert.equal(parseResult[0], 1000002, "Amount deposited to operator");
    assert.equal(
      parseResult[1],
      destinationEthereumAddress,
      "User lock ethereum address"
    );
    assert.equal(parseResult[2], 0, "Operator is first output");
  });
});

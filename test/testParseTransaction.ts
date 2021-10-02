import { assert, expect } from "chai";
import type { Contract } from "ethers";
import hre from "hardhat";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { deployContract } from "../deploy";

import {
  buildDogeTransaction,
  dogeAddressFromKeyPair,
  dogeKeyPairFromWIF,
  expectFailure,
  isolateTests,
  publicKeyHashFromKeyPair,
} from "./utils";

describe("testParseTransaction", () => {
  let dogeMessageLibraryForTests: Contract;
  let signers: SignerWithAddress[];
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

  it("Attempt to parse invalid transaction", async function () {
    const tx = buildDogeTransaction({
      signer: keys[1],
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
          address: dogeAddressFromKeyPair(keys[1]),
          value: 1000001,
        },
        {
          type: "payment",
          address: dogeAddressFromKeyPair(keys[0]),
          value: 1000002,
        },
      ],
    });
    const operatorPublicKeyHash = publicKeyHashFromKeyPair(keys[0]);
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
      signer: keys[1],
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
          address: dogeAddressFromKeyPair(keys[0]),
          value: 100000,
        },
      ],
    });
    const operatorPublicKeyHash = publicKeyHashFromKeyPair(keys[1]);
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

  it("Parse lock transaction", async function () {
    const operatorKeyPair = keys[0];
    const destinationEthereumAddress = signers[3].address;
    const decodedDestination = Buffer.from(
      destinationEthereumAddress.slice(2),
      "hex"
    );
    const lockAmount = 1000002;
    const tx = buildDogeTransaction({
      signer: keys[1],
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
          address: dogeAddressFromKeyPair(operatorKeyPair),
          value: lockAmount,
        },
        { type: "data embed", value: 0, data: decodedDestination },
        {
          type: "payment",
          address: dogeAddressFromKeyPair(keys[1]),
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

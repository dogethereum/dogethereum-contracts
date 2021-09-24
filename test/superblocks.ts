import hre from "hardhat";
import { assert } from "chai";
import type { Contract, ContractTransaction } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { deployFixture, deployContract } from "../deploy";

import {
  calcSuperblockHash,
  getEvents,
  makeMerkle,
  isolateTests,
} from "./utils";

describe("DogeSuperblocks", function () {
  let superblocks: Contract;
  let claimerSuperblocks: Contract;
  let accounts: SignerWithAddress[];
  let superblockClaims: SignerWithAddress;

  isolateTests();

  before(async function () {
    accounts = await hre.ethers.getSigners();
    superblockClaims = accounts[1];

    const dogethereum = await deployFixture(hre);
    superblocks = await deployContract("DogeSuperblocks", [], hre, {
      signer: accounts[0],
      libraries: {
        DogeMessageLibrary: dogethereum.dogeMessageLibrary.address,
      },
    });
    claimerSuperblocks = superblocks.connect(superblockClaims);
    await superblocks.setSuperblockClaims(superblockClaims.address);
  });

  describe("Utils", function () {
    const oneHash = [
      "0x57a8a9a8de6131bf61f5d385318c10e29a5d826eed6adbdbeedc3a0539908ed4",
    ];
    const twoHashes = [
      "0x2e6e9539f02088efe5abb7082bb6e8ba8df68e1cca543af48f5cc93523bf7209",
      "0x5db4c5556edb6dffe30eb26811327678a54f74b7a3072f2834472ea30ee17360",
    ];
    const threeHashes = [
      "0x6bbe42a26ec5af04eb16da92131ddcd87df55d629d940eaa8f88c0ceb0b9ede6",
      "0xc2213074ba6cf84780030f9dc261fa31999c039811516aaf0fb8fd1e1a9fa0c3",
      "0xde3d260197746a0b509ffa4e05cc8b042f0a0ce472c20d75e17bf58815d395e1",
    ];
    const manyHashes = [
      "0xb2d645742da1443e2439dfe1ee5901aa74680ddd2f11be203595673be5cfc396",
      "0x75520841e64a8acdd669e453d0a55caa7082a35ec6406cf5e73b30cdf34ad0b6",
      "0x6a4a7fdf807e56a39ca842d3e3807e6639af4cf1d05cf6da6154a0b5170f7690",
      "0xde3d260197746a0b509ffa4e05cc8b042f0a0ce472c20d75e17bf58815d395e1",
      "0x6bbe42a26ec5af04eb16da92131ddcd87df55d629d940eaa8f88c0ceb0b9ede6",
      "0x50ab8816b4a1ffa5700ff26bb1fbacce5e3cb93978e57410cfabbe8819a45a4e",
      "0x2e6e9539f02088efe5abb7082bb6e8ba8df68e1cca543af48f5cc93523bf7209",
      "0x57a8a9a8de6131bf61f5d385318c10e29a5d826eed6adbdbeedc3a0539908ed4",
      "0xceace0419d93c9789498de2ed1e75db53143b730f18cff88660297759c719231",
      "0x0ce3bcd684f4f795e549a2ddd1f4c539e8d80813b232a448c56d6b28b74fe3ed",
      "0x5db4c5556edb6dffe30eb26811327678a54f74b7a3072f2834472ea30ee17360",
      "0x03d7be19e9e961691712fde9fd87b706c7d0768a207b84ef6ad1f81ffa90dec5",
      "0x8e5e221b22795d96d3de1cad930d7b131f37b6b9dfcccd3f745b08e6900ef1bd",
      "0xc2213074ba6cf84780030f9dc261fa31999c039811516aaf0fb8fd1e1a9fa0c3",
      "0x38d3dffed604f5a160b327ecde5147eb1aa46e3d154b98644cd2a39f0f9ab915",
    ];

    isolateTests();

    it("Merkle javascript", async function () {
      let hash = makeMerkle(oneHash);
      assert.equal(
        hash,
        "0x57a8a9a8de6131bf61f5d385318c10e29a5d826eed6adbdbeedc3a0539908ed4",
        "One hash array"
      );
      hash = makeMerkle(twoHashes);
      assert.equal(
        hash,
        "0xae1c24c61efe6b378017f6055b891dd62747deb23a7939cffe78002f1cfb79ab",
        "Two hashes array"
      );
      hash = makeMerkle(threeHashes);
      assert.equal(
        hash,
        "0xe1c52ec93d4f4f83783aeede9e6b84b5ded007ec9591b521d6e5e4b6d9512d43",
        "Three hashes array"
      );
      hash = makeMerkle(manyHashes);
      assert.equal(
        hash,
        "0xee712eefe9b4c9ecd39a71d45e975b83c9427070e54953559e78f45d2cbb03b3",
        "Many hashes array"
      );
    });

    it("Merkle solidity", async function () {
      let hash = await superblocks.makeMerkle(oneHash);
      assert.equal(
        hash,
        "0x57a8a9a8de6131bf61f5d385318c10e29a5d826eed6adbdbeedc3a0539908ed4",
        "One hash array"
      );
      hash = await superblocks.makeMerkle(twoHashes);
      assert.equal(
        hash,
        "0xae1c24c61efe6b378017f6055b891dd62747deb23a7939cffe78002f1cfb79ab",
        "Two hashes array"
      );
      hash = await superblocks.makeMerkle(threeHashes);
      assert.equal(
        hash,
        "0xe1c52ec93d4f4f83783aeede9e6b84b5ded007ec9591b521d6e5e4b6d9512d43",
        "Three hashes array"
      );
      hash = await superblocks.makeMerkle(manyHashes);
      assert.equal(
        hash,
        "0xee712eefe9b4c9ecd39a71d45e975b83c9427070e54953559e78f45d2cbb03b3",
        "Many hashes array"
      );
    });

    it("Superblock id", async function () {
      const merkleRoot =
        "0xbc89818e52613f36d6cea2edba2c9417f01ee910250dbd85a8647a92e655996b";
      const accumulatedWork =
        "0x0000000000000000000000000000000000000000000000000000000000000023";
      const timestamp =
        "0x000000000000000000000000000000000000000000000000000000005ada05b9";
      const prevTimestamp =
        "0x000000000000000000000000000000000000000000000000000000005ada05b9";
      const lastHash =
        "0xe0dd609916339ee7e12272cf5467cf5915d2d41a16816e7118116fb281337367";
      const lastBits = "0x00000000";
      const parentId =
        "0xe70a134b97a4381e5b6c1f4ae0e1e3726b7284bf03506afacebf92401e255e97";
      const superblockHash = calcSuperblockHash(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        parentId
      );
      const id = await superblocks.calcSuperblockHash(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        parentId
      );
      assert.equal(id, superblockHash, "Superblock hash should match");
    });
  });

  describe("Verify status transitions", function () {
    let id0: string;
    let id1: string;
    let id2: string;
    let id3: string;
    const merkleRoot = makeMerkle([
      "0x0000000000000000000000000000000000000000000000000000000000000000",
    ]);
    const accumulatedWork = 0;
    const timestamp = 1;
    const prevTimestamp = 0;
    const lastBits = 0;
    const lastHash =
      "0x0000000000000000000000000000000000000000000000000000000000000000";
    const parentHash =
      "0x0000000000000000000000000000000000000000000000000000000000000000";

    isolateTests();

    it("Initialized", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.initialize(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        parentHash
      );
      const { events: newSuperblockEvents } = await getEvents(
        tx,
        "NewSuperblock"
      );

      assert.lengthOf(newSuperblockEvents, 1, "New superblock proposed");
      id0 = newSuperblockEvents[0].args!.superblockHash;
    });

    it("Propose", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.propose(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        id0,
        superblockClaims.address
      );
      const { events: newSuperblockEvents } = await getEvents(
        tx,
        "NewSuperblock"
      );

      assert.lengthOf(newSuperblockEvents, 1, "New superblock proposed");
      id1 = newSuperblockEvents[0].args!.superblockHash;
    });

    it("Bad propose", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.propose(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        id0,
        superblockClaims.address
      );
      const { events: errorSuperblockEvents } = await getEvents(
        tx,
        "ErrorSuperblock"
      );

      assert.lengthOf(errorSuperblockEvents, 1, "Superblock already exists");
    });

    it("Bad parent", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.propose(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        superblockClaims.address
      );
      const { events: errorSuperblockEvents } = await getEvents(
        tx,
        "ErrorSuperblock"
      );

      assert.lengthOf(
        errorSuperblockEvents,
        1,
        "Superblock parent does not exist"
      );
    });

    it("Approve", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.confirm(
        id1,
        superblockClaims.address
      );
      const { events: approvedSuperblockEvents } = await getEvents(
        tx,
        "ApprovedSuperblock"
      );

      assert.lengthOf(approvedSuperblockEvents, 1, "Superblock confirmed");
    });

    it("Propose bis", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.propose(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        id1,
        superblockClaims.address
      );
      const { events: newSuperblockEvents } = await getEvents(
        tx,
        "NewSuperblock"
      );

      assert.lengthOf(newSuperblockEvents, 1, "New superblock proposed");
      id2 = newSuperblockEvents[0].args!.superblockHash;
    });

    it("Challenge", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.challenge(
        id2,
        superblockClaims.address
      );
      const { events: challengeSuperblockEvents } = await getEvents(
        tx,
        "ChallengeSuperblock"
      );

      assert.lengthOf(challengeSuperblockEvents, 1, "Superblock challenged");
    });

    it("Semi-Approve", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.semiApprove(
        id2,
        superblockClaims.address
      );
      const { events: semiApprovedEvents } = await getEvents(
        tx,
        "SemiApprovedSuperblock"
      );
      assert.lengthOf(semiApprovedEvents, 1, "Superblock semi-approved");
    });

    it("Approve bis", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.confirm(
        id2,
        superblockClaims.address
      );
      const { events: approvedEvents } = await getEvents(
        tx,
        "ApprovedSuperblock"
      );
      assert.lengthOf(approvedEvents, 1, "Superblock confirmed");
    });

    it("Invalidate bad", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.invalidate(
        id2,
        superblockClaims.address
      );
      const { events: errorEvents } = await getEvents(tx, "ErrorSuperblock");
      assert.lengthOf(errorEvents, 1, "Superblock cannot invalidate");
    });

    it("Propose tris", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.propose(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        id2,
        superblockClaims.address
      );
      const { events: newSuperblockEvents } = await getEvents(
        tx,
        "NewSuperblock"
      );
      assert.lengthOf(newSuperblockEvents, 1, "New superblock proposed");
      id3 = newSuperblockEvents[0].args!.superblockHash;
    });

    it("Challenge bis", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.challenge(
        id3,
        superblockClaims.address
      );
      const { events: challengeEvents } = await getEvents(
        tx,
        "ChallengeSuperblock"
      );
      assert.lengthOf(challengeEvents, 1, "Superblock challenged");
    });

    it("Invalidate", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.invalidate(
        id3,
        superblockClaims.address
      );
      const { events: invalidSuperblockEvents } = await getEvents(
        tx,
        "InvalidSuperblock"
      );
      assert.lengthOf(invalidSuperblockEvents, 1, "Superblock invalidated");
    });

    it("Approve bad", async function () {
      const tx: ContractTransaction = await claimerSuperblocks.confirm(
        id3,
        superblockClaims.address
      );
      const { events: errorSuperblockEvents } = await getEvents(
        tx,
        "ErrorSuperblock"
      );
      assert.lengthOf(errorSuperblockEvents, 1, "Superblock cannot approve");
    });
  });

  describe("Only SuperblockClaims can modify", function () {
    let id0: string;
    let id1: string;
    let id2: string;
    let id3: string;
    const merkleRoot = makeMerkle([
      "0x0000000000000000000000000000000000000000000000000000000000000000",
    ]);
    const accumulatedWork = 0;
    const timestamp = Math.floor(new Date().getTime() / 1000);
    const prevTimestamp = timestamp - 1;
    const lastBits = 0;
    const lastHash =
      "0x0000000000000000000000000000000000000000000000000000000000000000";
    const parentHash =
      "0x0000000000000000000000000000000000000000000000000000000000000000";

    isolateTests();

    it("Initialized", async function () {
      const tx: ContractTransaction = await superblocks.initialize(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        parentHash
      );
      const { events: newSuperblockEvents } = await getEvents(
        tx,
        "NewSuperblock"
      );
      assert.lengthOf(newSuperblockEvents, 1, "New superblock proposed");
      id0 = newSuperblockEvents[0].args!.superblockHash;
    });

    it("Propose", async function () {
      let result: ContractTransaction = await superblocks.propose(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        id0,
        superblockClaims.address
      );
      const { events: errorSuperblockEvents } = await getEvents(
        result,
        "ErrorSuperblock"
      );
      assert.lengthOf(
        errorSuperblockEvents,
        1,
        "Only superblockClaims can propose"
      );

      result = await claimerSuperblocks.propose(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        id0,
        superblockClaims.address
      );
      const { events: newSuperblockEvents } = await getEvents(
        result,
        "NewSuperblock"
      );
      assert.lengthOf(newSuperblockEvents, 1, "SuperblockClaims can propose");
      id1 = newSuperblockEvents[0].args!.superblockHash;
    });

    it("Approve", async function () {
      let result: ContractTransaction = await superblocks.confirm(
        id1,
        superblockClaims.address
      );
      const { events: errorSuperblockEvents } = await getEvents(
        result,
        "ErrorSuperblock"
      );
      assert.lengthOf(
        errorSuperblockEvents,
        1,
        "Only superblockClaims can propose"
      );

      result = await claimerSuperblocks.confirm(id1, superblockClaims.address);
      const { events: approvedEvents } = await getEvents(
        result,
        "ApprovedSuperblock"
      );
      assert.lengthOf(approvedEvents, 1, "Only superblockClaims can confirm");
    });

    it("Challenge", async function () {
      let result: ContractTransaction = await claimerSuperblocks.propose(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        id1,
        superblockClaims.address
      );
      const { events: newSuperblockEvents } = await getEvents(
        result,
        "NewSuperblock"
      );
      assert.lengthOf(newSuperblockEvents, 1, "SuperblockClaims can propose");
      id2 = newSuperblockEvents[0].args!.superblockHash;

      result = await superblocks.challenge(id2, superblockClaims.address);
      const { events: errorSuperblockEvents } = await getEvents(
        result,
        "ErrorSuperblock"
      );
      assert.lengthOf(
        errorSuperblockEvents,
        1,
        "Only superblockClaims can propose"
      );

      result = await claimerSuperblocks.challenge(
        id2,
        superblockClaims.address
      );
      const { events: challengeEvents } = await getEvents(
        result,
        "ChallengeSuperblock"
      );
      assert.lengthOf(challengeEvents, 1, "Superblock challenged");
    });

    it("Semi-Approve", async function () {
      let result: ContractTransaction = await superblocks.semiApprove(
        id2,
        superblockClaims.address
      );
      const { events: errorSuperblockEvents } = await getEvents(
        result,
        "ErrorSuperblock"
      );
      assert.lengthOf(
        errorSuperblockEvents,
        1,
        "Only superblockClaims can semi-approve"
      );

      result = await claimerSuperblocks.semiApprove(
        id2,
        superblockClaims.address
      );
      const { events: semiApprovedEvents } = await getEvents(
        result,
        "SemiApprovedSuperblock"
      );
      assert.lengthOf(semiApprovedEvents, 1, "Superblock semi-approved");

      result = await claimerSuperblocks.confirm(id2, superblockClaims.address);
      const { events: approvedEvents } = await getEvents(
        result,
        "ApprovedSuperblock"
      );
      assert.lengthOf(approvedEvents, 1, "superblockClaims cannot confirm");
    });

    it("Invalidate", async function () {
      let result: ContractTransaction = await claimerSuperblocks.propose(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        id2,
        superblockClaims.address
      );
      const { events: newSuperblockEvents } = await getEvents(
        result,
        "NewSuperblock"
      );
      assert.lengthOf(newSuperblockEvents, 1, "New superblock proposed");
      id3 = newSuperblockEvents[0].args!.superblockHash;

      result = await claimerSuperblocks.challenge(
        id3,
        superblockClaims.address
      );
      const { events: challengeEvents } = await getEvents(
        result,
        "ChallengeSuperblock"
      );
      assert.lengthOf(challengeEvents, 1, "Superblock challenged");

      result = await superblocks.invalidate(id3, superblockClaims.address);
      const { events: errorSuperblockEvents } = await getEvents(
        result,
        "ErrorSuperblock"
      );
      assert.lengthOf(
        errorSuperblockEvents,
        1,
        "Only superblockClaims can invalidate"
      );

      result = await claimerSuperblocks.invalidate(
        id3,
        superblockClaims.address
      );
      const { events: invalidSuperblockEvents } = await getEvents(
        result,
        "InvalidSuperblock"
      );
      assert.lengthOf(invalidSuperblockEvents, 1, "Superblock invalidated");
    });
  });

  describe("Test locator", function () {
    let id0: string;
    const merkleRoot = makeMerkle([
      "0x0000000000000000000000000000000000000000000000000000000000000000",
    ]);
    const accumulatedWork = 0;
    const timestamp = 1;
    const prevTimestamp = 0;
    const lastBits = 0;
    const lastHash =
      "0x0000000000000000000000000000000000000000000000000000000000000000";
    const parentHash =
      "0x0000000000000000000000000000000000000000000000000000000000000000";

    isolateTests();

    it("Initialized", async function () {
      const tx: ContractTransaction = await superblocks.initialize(
        merkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        parentHash
      );
      const { events: newSuperblockEvents } = await getEvents(
        tx,
        "NewSuperblock"
      );
      assert.lengthOf(newSuperblockEvents, 1, "New superblock proposed");
      id0 = newSuperblockEvents[0].args!.superblockHash;
    });

    it("Verify locator", async function () {
      let parentId = id0;
      let superblockHash;
      let locator = await superblocks.getSuperblockLocator();
      const sblocks: Record<number, string> = { 0: id0 };
      for (let work = 1; work < 30; ++work) {
        let result: ContractTransaction = await claimerSuperblocks.propose(
          merkleRoot,
          work,
          0,
          0,
          lastHash,
          lastBits,
          parentId,
          superblockClaims.address
        );
        const { events: newSuperblockEvents } = await getEvents(
          result,
          "NewSuperblock"
        );
        assert.lengthOf(newSuperblockEvents, 1, "SuperblockClaims can propose");
        superblockHash = newSuperblockEvents[0].args!.superblockHash;

        result = await claimerSuperblocks.confirm(
          superblockHash,
          superblockClaims.address
        );
        const { events: approvedEvents } = await getEvents(
          result,
          "ApprovedSuperblock"
        );
        assert.lengthOf(approvedEvents, 1, "Only superblockClaims can propose");

        locator = await superblocks.getSuperblockLocator();
        assert.equal(
          locator[0],
          superblockHash,
          "Position 0 current best superblock"
        );
        assert.equal(locator[1], parentId, "Position 1 parent best superblock");
        let step = 5;
        // At index i we have superblockHash of height
        // (bestSuperblock-1) - (bestSuperblock-1) % 5**(i-1)
        for (let i = 2; i <= 8; ++i) {
          const pos = work - 1 - ((work - 1) % step);
          assert.equal(
            locator[i],
            sblocks[pos],
            `Invalid superblock at ${i} ${step} ${pos}`
          );
          step = step * 5;
        }
        if (work % 5 === 0) {
          sblocks[work] = superblockHash;
        }
        parentId = superblockHash;
      }
    });
  });
});

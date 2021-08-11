import hre from "hardhat";
import { assert } from "chai";
import type { Contract } from "ethers";

import { isolateTests } from "./utils";

describe("sliceArray", function () {
  let dogeMessageLibraryForTests: Contract;

  isolateTests();

  before(async () => {
    const DogeMessageLibraryForTests = await hre.ethers.getContractFactory(
      "DogeMessageLibraryForTests"
    );
    dogeMessageLibraryForTests = await DogeMessageLibraryForTests.deploy();
  });

  it("slice middle", async () => {
    const result = await dogeMessageLibraryForTests.callStatic.sliceArrayPublic(
      "0x000102030405060708090a",
      2,
      5
    );
    assert.equal(result.toString(16), "0x020304", "Slice failed");
  });

  it("slice begin", async () => {
    const result = await dogeMessageLibraryForTests.callStatic.sliceArrayPublic(
      "0x000102030405060708090a",
      0,
      3
    );
    assert.equal(result.toString(16), "0x000102", "Slice failed");
  });

  it("slice end", async () => {
    const result = await dogeMessageLibraryForTests.callStatic.sliceArrayPublic(
      "0x000102030405060708090a",
      8,
      11
    );
    assert.equal(result.toString(16), "0x08090a", "Slice failed");
  });

  it("slice all", async () => {
    const result = await dogeMessageLibraryForTests.callStatic.sliceArrayPublic(
      "0x0100000050120119172a610421a6c3011dd330d9df07b63616c2cc1f1cd00200000000006657a9252aacd5c0b2940996ecff952228c3067cc38d4885efb5a4ac4247e9f337221b4d4c86041b0f2b5710",
      0,
      80
    );
    assert.equal(
      result.toString(16),
      "0x0100000050120119172a610421a6c3011dd330d9df07b63616c2cc1f1cd00200000000006657a9252aacd5c0b2940996ecff952228c3067cc38d4885efb5a4ac4247e9f337221b4d4c86041b0f2b5710",
      "Slice failed"
    );
  });
});

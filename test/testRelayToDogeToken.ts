import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { assert } from "chai";
import type { Contract, ContractTransaction } from "ethers";
import hre from "hardhat";

import { deployFixture } from "../deploy";

import {
  blockchainTimeoutSeconds,
  buildDogeTransaction,
  DEPOSITS,
  dogeAddressFromKeyPair,
  dogeKeyPairFromWIF,
  makeMerkle,
  makeMerkleProof,
  makeSuperblock,
  isolateTests,
  OPTIONS_DOGE_REGTEST,
  publicKeyHashFromKeyPair,
  remove0x,
} from "./utils";

describe("testRelayToDogeToken", function () {
  let dogeToken: Contract;
  let superblocks: Contract;
  let superblockClaims: Contract;
  let signers: SignerWithAddress[];

  const userEthAddress = "0x30d90d1dbf03aa127d58e6af83ca1da9e748c98d";
  const value = 905853205327;
  const operatorFee = 9058532053;
  const superblockSubmitterFee = 9058532053;
  const userValue = value - operatorFee - superblockSubmitterFee;

  const keypairs = [
    "QSRUX7i1WVzFW6vx3i4Qj8iPPQ1tRcuPanMun8BKf8ySc8LsUuKx",
    "QULAK58teBn1Xi4eGo4fKea5oQDPMK4vcnmnivqzgvCPagsWHiyf",
  ].map(dogeKeyPairFromWIF);

  const operatorDogeAddress = dogeAddressFromKeyPair(keypairs[0]);

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
      { type: "payment", address: operatorDogeAddress, value },
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
  const numberOfTxs = 14;
  const txIndex = 5;
  const allTxIdsInBlock = createFakeTxIds(numberOfTxs, txHash, txIndex);

  isolateTests();

  before(async () => {
    ({ superblockClaims, superblocks, dogeToken } = await deployFixture(hre));
    signers = await hre.ethers.getSigners();
  });

  it("Relay lock tx to token", async function () {
    const operatorEthAddress = signers[3].address;
    await dogeToken.addOperatorSimple(
      operatorPublicKeyHash,
      operatorEthAddress
    );

    const superblockSubmitterSigner = signers[4];
    const submitterSuperblocks = superblocks.connect(superblockSubmitterSigner);
    const submitterSuperblockClaims = superblockClaims.connect(
      superblockSubmitterSigner
    );

    const totalBlocks = 10;
    const blockIndex = 4;
    const headers = createFakeBlockHeaders(
      totalBlocks,
      allTxIdsInBlock,
      blockIndex + 1
    );

    const genesisHeaders = headers.slice(0, 1);
    const genesisSuperblock = makeSuperblock(
      genesisHeaders,
      "0x0000000000000000000000000000000000000000000000000000000000000000",
      0,
      1448429041 // timestamp block 974400
    );

    await submitterSuperblocks.initialize(
      genesisSuperblock.merkleRoot,
      genesisSuperblock.accumulatedWork,
      genesisSuperblock.timestamp,
      genesisSuperblock.prevTimestamp,
      genesisSuperblock.lastHash,
      genesisSuperblock.lastBits,
      genesisSuperblock.parentId
    );

    const newHeaders = headers.slice(1);
    const proposedSuperblock = makeSuperblock(
      newHeaders,
      genesisSuperblock.superblockHash,
      genesisSuperblock.accumulatedWork
    );

    await submitterSuperblockClaims.makeDeposit({
      value: DEPOSITS.MIN_PROPOSAL_DEPOSIT,
    });

    let result: ContractTransaction = await submitterSuperblockClaims.proposeSuperblock(
      proposedSuperblock.merkleRoot,
      proposedSuperblock.accumulatedWork,
      proposedSuperblock.timestamp,
      proposedSuperblock.prevTimestamp,
      proposedSuperblock.lastHash,
      proposedSuperblock.lastBits,
      proposedSuperblock.parentId
    );
    let receipt = await result.wait();

    const superblockClaimCreatedEvents = receipt.events!.filter(
      (event) => event.event === "SuperblockClaimCreated"
    );
    assert.lengthOf(
      superblockClaimCreatedEvents,
      1,
      "New superblock should be proposed"
    );
    const superblockHash = receipt.events![1].args!.superblockHash;

    await blockchainTimeoutSeconds(3 * OPTIONS_DOGE_REGTEST.TIMEOUT);

    result = await submitterSuperblockClaims.checkClaimFinished(superblockHash);
    receipt = await result.wait();
    const superblockClaimSuccessfulEvents = receipt.events!.filter(
      (event) => event.event === "SuperblockClaimSuccessful"
    );
    assert.lengthOf(
      superblockClaimSuccessfulEvents,
      1,
      "Superblock claim should be successful"
    );

    const txMerkleProof = makeMerkleProof(
      allTxIdsInBlock.map(remove0x),
      txIndex
    );
    const txSiblingsProof = txMerkleProof.sibling.map(
      (sibling) => `0x${sibling}`
    );

    const blockHeader = `0x${newHeaders[blockIndex]}`;
    const blockMerkleProof = makeMerkleProof(
      proposedSuperblock.blockHashes,
      blockIndex
    );
    const blockSiblings = blockMerkleProof.sibling.map(
      (sibling) => `0x${sibling}`
    );

    result = await submitterSuperblocks.relayLockTx(
      txData,
      operatorPublicKeyHash,
      txIndex,
      txSiblingsProof,
      blockHeader,
      blockIndex,
      blockSiblings,
      proposedSuperblock.superblockHash,
      dogeToken.address
    );
    receipt = await result.wait();

    const relayTxEvents = receipt.events!.filter(
      (log) => log.event === "RelayTransaction"
    );
    assert.lengthOf(relayTxEvents, 1);
    const ERR_RELAY_VERIFY = 30010;
    assert.notEqual(
      relayTxEvents[0].args!.returnCode.toNumber(),
      ERR_RELAY_VERIFY,
      "RelayTransaction failed"
    );

    const balance = await dogeToken.balanceOf(userEthAddress);
    assert.equal(
      balance.toString(),
      userValue,
      `DogeToken user (${userEthAddress}) balance is not the expected one`
    );
    const operatorTokenBalance = await dogeToken.balanceOf(operatorEthAddress);
    assert.equal(
      operatorTokenBalance.toNumber(),
      operatorFee,
      `DogeToken operator (${operatorEthAddress}) balance is not the expected one`
    );
    const superblockSubmitterTokenBalance = await dogeToken.balanceOf(
      superblockSubmitterSigner.address
    );
    assert.equal(
      superblockSubmitterTokenBalance.toNumber(),
      superblockSubmitterFee,
      `DogeToken superblock submitter (${superblockSubmitterSigner.address}) balance is not the expected one`
    );

    const operator = await dogeToken.operators(operatorPublicKeyHash);
    assert.equal(
      operator.dogeAvailableBalance.toString(),
      value,
      "operator dogeAvailableBalance is not the expected one"
    );
  });

  // TODO: implement these tests
  it.skip("Relay unlock tx to token", function () {
    assert.fail("Test not implemented.");
  });

  it.skip("Relay two unlock txs to token", function () {
    assert.fail("Test not implemented.");
  });
});

// Creates fake "pure" headers. These lack the AuxPOW bits used for merged mining.
// See https://github.com/dogecoin/dogecoin/blob/master/src/primitives/pureheader.h
function createFakeTxIds(
  numberOfTxs: number,
  realTxId: string,
  realTxIndex = numberOfTxs - 1
) {
  if (realTxIndex < 0 || realTxIndex >= numberOfTxs) {
    throw new Error(
      "The selected tx index should be in range of the number of txs to be created."
    );
  }

  const txIds = [];
  for (let i = 0; i < numberOfTxs; i++) {
    const txId = i === realTxIndex ? realTxId : fakeUint256LE(i);
    txIds.push(txId);
  }

  return txIds;
}

// Creates fake "pure" headers. These lack the AuxPOW bits used for merged mining.
// See https://github.com/dogecoin/dogecoin/blob/master/src/primitives/pureheader.h
function createFakeBlockHeaders(
  numberOfHeaders: number,
  txIds: string[],
  txBlockIndex = numberOfHeaders - 1
) {
  if (txBlockIndex < 0 || txBlockIndex >= numberOfHeaders) {
    throw new Error(
      "The selected block index should be in range of the number of block headers to be created."
    );
  }

  const headers = [];
  const baseDifficulty = 0x0b041a48;
  for (let i = 0; i < numberOfHeaders; i++) {
    const fakeField = fakeUint256LE(i);
    const merkleRoot: string =
      i === txBlockIndex ? makeMerkle(txIds) : fakeField;
    const difficultyBits = fakeUint32LE(baseDifficulty + i);
    const header = craftFakeHeader(fakeField, merkleRoot, difficultyBits);
    headers.push(header);
  }

  return headers;
}

/**
 * @param previousBlockHash Hexadecimal encoded hash
 * @param merkleRoot Hexadecimal encoded merkle root
 * @param difficultyBits Hexadecimal encoded bits
 */
function craftFakeHeader(
  previousBlockHash: string,
  merkleRoot: string,
  difficultyBits: string
): string {
  // This version field has the AuxPOW flag off
  const version = Buffer.from("00620003", "hex").reverse().toString("hex");
  const time = Buffer.from("609c19ea", "hex").reverse().toString("hex");
  const nonce = "7e57577e";
  return `${version}${remove0x(previousBlockHash)}${reverseDataBytes(
    merkleRoot
  )}${time}${remove0x(difficultyBits)}${nonce}`;
}

function fakeUint256LE(seed: number): string {
  const uint256Size = 32;
  const testString = Buffer.from("test header").toString("hex");
  const seedString = remove0x(hre.ethers.utils.hexlify(seed));
  const payload = hre.ethers.utils.hexZeroPad(
    `0x${testString}${seedString}`,
    uint256Size
  );
  return payload;
}

function fakeUint32LE(seed: number): string {
  const uint32Size = 4;
  const payload = Buffer.from(
    remove0x(hre.ethers.utils.hexlify(seed)),
    "hex"
  ).reverse();
  return hre.ethers.utils.hexZeroPad(payload, uint32Size);
}

function reverseDataBytes(data: string) {
  return Buffer.from(remove0x(data), "hex").reverse().toString("hex");
}

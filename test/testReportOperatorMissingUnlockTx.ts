import { assert } from "chai";
import hre from "hardhat";
import type { Contract, ContractTransaction } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { deployFixture, deployToken, TokenOptions } from "../deploy";

import {
  buildDogeTransaction,
  dogeAddressFromKeyPair,
  dogeKeyPairFromWIF,
  expectFailure,
  getEvents,
  isolateEachTest,
  isolateTests,
  makeMerkle,
  publicKeyHashFromKeyPair,
} from "./utils";

describe("Token - report operator missing unlock tx", function () {
  let signers: SignerWithAddress[];
  let trustedRelayerContract: string;
  let operatorEthAddress: string;
  let superblockClaimsAddress: string;
  const tokenOptions: TokenOptions = {
    collateralRatio: 2,
    unlockEthereumTimeGracePeriod: 4 * 60 * 60,
    unlockSuperblocksHeightGracePeriod: 4,
  };

  let claimerSuperblocks: Contract;

  let unlockId: number;

  let userEthSigner: SignerWithAddress;
  const value = 905853205327;
  // const change = 458205327;

  const keypairs = [
    "QSRUX7i1WVzFW6vx3i4Qj8iPPQ1tRcuPanMun8BKf8ySc8LsUuKx",
    "QULAK58teBn1Xi4eGo4fKea5oQDPMK4vcnmnivqzgvCPagsWHiyf",
  ].map(dogeKeyPairFromWIF);
  const operatorKeypair = keypairs[0];
  const userKeypair = keypairs[1];

  // const operatorDogeAddress = dogeAddressFromKeyPair(operatorKeypair);
  const operatorPublicKeyHash = publicKeyHashFromKeyPair(operatorKeypair);

  const userAddress = dogeAddressFromKeyPair(userKeypair);
  const userPublicKeyHash = publicKeyHashFromKeyPair(userKeypair);

  const utxoRef = {
    txId: "edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67",
    index: 0,
  };

  let dogeToken: Contract;

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

  const unlockRequest = {
    name: "unlock without change",
    utxoValue: value - operatorFee,
    requestValue: value,
    data: `0x${unlockTx.toHex()}`,
    hash: `0x${unlockTx.getId()}`,
  };

  isolateTests();
  isolateEachTest();

  before(async function () {
    signers = await hre.ethers.getSigners();
    const {
      dogeToken: fixtureToken,
      superblocks,
      superblockClaims,
    } = await deployFixture(hre);
    // Tell DogeToken to trust signers[0] as if it were the relayer contract
    trustedRelayerContract = signers[0].address;
    operatorEthAddress = signers[3].address;
    superblockClaimsAddress = superblockClaims.address;
    userEthSigner = signers[5];

    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [superblockClaimsAddress],
    });
    const claimerSigner = await hre.ethers.getSigner(superblockClaimsAddress);
    claimerSuperblocks = superblocks.connect(claimerSigner);

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
    unlockId = await dogeToken.unlockIdx();
    const userDogeToken = dogeToken.connect(userEthSigner);
    await userDogeToken.doUnlock(
      userPublicKeyHash,
      unlockRequest.requestValue,
      operatorPublicKeyHash
    );
  });

  after(function () {
    return hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [superblockClaimsAddress],
    });
  });

  it("liquidates an operator that fails to relay unlock tx", async function () {
    await hre.network.provider.request({
      method: "hardhat_setBalance",
      params: [superblockClaimsAddress, "0x1000000000000000000"],
    });
    await initAndAddSuperblocks(25, claimerSuperblocks, operatorEthAddress);
    await hre.network.provider.request({
      method: "evm_increaseTime",
      params: [25 * 60 * 60],
    });

    const tx = await dogeToken.reportOperatorMissingUnlock(
      operatorPublicKeyHash,
      unlockId
    );

    const { events: liquidateEvents } = await getEvents(
      tx,
      "OperatorLiquidated"
    );
    assert.lengthOf(liquidateEvents, 1, "Operator wasn't liquidated.");
  });

  it("fails to liquidate an operator if not enough superblocks were confirmed", async function () {
    await hre.network.provider.request({
      method: "evm_increaseTime",
      params: [25 * 60 * 60],
    });

    await expectFailure(
      () =>
        dogeToken.reportOperatorMissingUnlock(operatorPublicKeyHash, unlockId),
      (error) => {
        assert.include(
          error.message,
          "unlock is still within the superblockchain height grace period"
        );
      }
    );
  });

  it("fails to liquidate an operator if not enough time has elapsed in ethereum", async function () {
    await expectFailure(
      () =>
        dogeToken.reportOperatorMissingUnlock(operatorPublicKeyHash, unlockId),
      (error) => {
        assert.include(
          error.message,
          "unlock is still within the time grace period"
        );
      }
    );
  });
});

async function initAndAddSuperblocks(
  amount: number,
  claimerSuperblocks: Contract,
  submitter: string
) {
  const merkleRoot = makeMerkle([
    "0x0000000000000000000000000000000000000000000000000000000000000000",
  ]);
  let accumulatedWork = 0;
  const timestamp = 1;
  const prevTimestamp = 0;
  const lastBits = 0;
  const lastHash =
    "0x0000000000000000000000000000000000000000000000000000000000000000";
  const parentHash =
    "0x0000000000000000000000000000000000000000000000000000000000000000";

  const tx: ContractTransaction = await claimerSuperblocks.initialize(
    merkleRoot,
    accumulatedWork,
    timestamp,
    prevTimestamp,
    lastHash,
    lastBits,
    parentHash
  );
  const { events: newSuperblockEvents } = await getEvents(tx, "NewSuperblock");

  let lastSuperblockId: string = newSuperblockEvents[0].args!.superblockHash;

  for (let i = 0; i < amount; i++) {
    // We need to increment the accumulated work to ensure the superblockchain updates the best superblock.
    // TODO: does this make sense? Should the superblockchain update the best superblock regardless of accumulatedWork?
    accumulatedWork += 1;

    let tx: ContractTransaction = await claimerSuperblocks.propose(
      merkleRoot,
      accumulatedWork,
      timestamp,
      prevTimestamp,
      lastHash,
      lastBits,
      lastSuperblockId,
      submitter
    );
    const { events: newSuperblockEvents } = await getEvents(
      tx,
      "NewSuperblock"
    );

    assert.lengthOf(newSuperblockEvents, 1, "New superblock wasn't proposed");
    lastSuperblockId = newSuperblockEvents[0].args!.superblockHash;

    tx = await claimerSuperblocks.confirm(lastSuperblockId, submitter);
    const { events: approvedSuperblockEvents } = await getEvents(
      tx,
      "ApprovedSuperblock"
    );

    assert.lengthOf(approvedSuperblockEvents, 1, "Superblock didn't confirm");
  }
}

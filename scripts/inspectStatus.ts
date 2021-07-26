import type { Contract, Event, utils } from "ethers";
import type { HardhatRuntimeEnvironment } from "hardhat/types";
import type { DogethereumContract, DogethereumSystem } from "../deploy";

import { getWalletFor, Role } from "./signers";

export async function printStatus(
  hre: HardhatRuntimeEnvironment,
  deployment: DogethereumSystem
): Promise<void> {
  await printSuperblockchainStatus(deployment);

  await printSuperblockchainBattles(deployment);

  await printScryptStatus(deployment, hre);
  await printDogeTokenStatus(deployment, hre);
}

async function printScryptStatus(
  { scryptChecker }: DogethereumSystem,
  hre: HardhatRuntimeEnvironment
) {
  if (scryptChecker.name === "ScryptCheckerDummy") {
    console.log("No scrypt verification contract deployed.");
    console.log("");
    return;
  }

  console.log("ScryptClaims");
  console.log("---------");

  // idea: merge these into a single list and sort them by tx execution order?
  const scryptClaimEvents = [
    "ClaimCreated",
    "ClaimChallenged",
    "SessionDecided",
    "VerificationGameStarted",
    "ClaimVerificationGamesEnded",
    "ClaimSuccessful",
    "ClaimFailed",
  ];
  await printContractEvents(scryptClaimEvents, scryptChecker);
  console.log("");

  const scryptVerifierAddress = await scryptChecker.contract.callStatic.scryptVerifier();
  const scryptVerifierName = "ScryptVerifier";
  const scryptVerifier = await hre.ethers.getContractAt(
    scryptVerifierName,
    scryptVerifierAddress
  );

  console.log("ScryptVerifier");
  console.log("---------");

  // idea: merge these into a single list and sort them by tx execution order?
  const scryptVerifierEvents = [
    "NewSession",
    "NewQuery",
    "NewResponse",
    "ChallengerConvicted",
    "ClaimantConvicted",
  ];
  await printContractEvents(scryptVerifierEvents, {
    contract: scryptVerifier,
    name: scryptVerifierName,
  });
  console.log("");
}

async function printDogeTokenStatus(
  { dogeToken }: DogethereumSystem,
  hre: HardhatRuntimeEnvironment
) {
  console.log("DogeToken");
  console.log("---------");

  await showBalance(
    dogeToken.contract,
    "0x92ecc1ba4ea10f681dcf35c02f583e59d2b99b4b"
  );

  const userWallet = getWalletFor(Role.User);
  await showBalance(dogeToken.contract, userWallet.address);

  await showBalance(
    dogeToken.contract,
    "0xf5fa014271b7971cb0ae960d445db3cb3802dfd9"
  );

  const dogeEthPrice = await dogeToken.contract.callStatic.dogeEthPrice();
  console.log(`Doge-Eth price: ${dogeEthPrice}`);

  // Operators
  const operatorsLength = await dogeToken.contract.getOperatorsLength();
  console.log(`operators length: ${operatorsLength}`);
  for (let i = 0; i < operatorsLength; i++) {
    const {
      key: operatorPublicKeyHash,
      deleted,
    }: {
      key: string;
      deleted: boolean;
    } = await dogeToken.contract.operatorKeys(i);
    if (!deleted) {
      // not deleted
      const {
        ethAddress,
        dogeAvailableBalance,
        dogePendingBalance,
        nextUnspentUtxoIndex,
        ethBalance,
      } = await dogeToken.contract.operators(operatorPublicKeyHash);
      const utxosLength = await dogeToken.contract.getUtxosLength(
        operatorPublicKeyHash
      );
      console.log(
        `- operator [${operatorPublicKeyHash}]:
  - eth address: ${ethAddress}
    dogeAvailableBalance: ${dogeAvailableBalance}
    dogePendingBalance: ${dogePendingBalance}
    nextUnspentUtxoIndex: ${nextUnspentUtxoIndex}
    ethBalance: ${hre.web3.utils.fromWei(ethBalance.toString())}
    utxosLength: ${utxosLength}`
      );
      for (let j = 0; j < utxosLength; j++) {
        const { value, txHash, index } = await dogeToken.contract.getUtxo(
          operatorPublicKeyHash,
          j
        );
        console.log(
          `    utxo [${j}]: ${txHash.toHexString()}, ${index}, ${value}`
        );
      }
    }
  }

  // Current block number
  const ethBlockNumber = await hre.ethers.provider.getBlockNumber();
  console.log(`Eth Current block: ${ethBlockNumber}`);

  // TODO: print these like the others
  // Unlock events
  const unlockRequestFilter = dogeToken.contract.filters.UnlockRequest();
  const unlockRequestEvents = await dogeToken.contract.queryFilter(
    unlockRequestFilter,
    0,
    "latest"
  );
  await printUnlockEvent(unlockRequestEvents, dogeToken.contract);

  const dogeTokenEventNames = ["NewToken", "ErrorDogeToken"];

  await printContractEvents(dogeTokenEventNames, dogeToken);
}

async function printSuperblockchainStatus({
  superblocks: { contract: superblocks },
  superblockClaims,
}: DogethereumSystem) {
  console.log("Superblocks");
  console.log("---------");
  const bestSuperblockHash = await superblocks.callStatic.getBestSuperblock();
  console.log(`Best superblock hash: ${bestSuperblockHash.toString(16)}`);
  const bestSuperblockHeight = await superblocks.callStatic.getSuperblockHeight(
    bestSuperblockHash
  );
  console.log(`Best superblock height: ${bestSuperblockHeight}`);
  const lastHash = await superblocks.callStatic.getSuperblockLastHash(
    bestSuperblockHash
  );
  console.log(`lastHash: ${lastHash}`);
  const indexNextSuperblock = await superblocks.callStatic.getIndexNextSuperblock();
  console.log(`indexNextSuperblock: ${indexNextSuperblock}`);
  const newSuperblockEventTimestamp = await superblockClaims.contract.callStatic.getNewSuperblockEventTimestamp(
    bestSuperblockHash
  );
  console.log(`newSuperblockEventTimestamp: ${newSuperblockEventTimestamp}`);
  // idea: merge these into a single list and sort them by tx execution order?
  const superblockClaimEvents = [
    "SuperblockClaimCreated",
    "SuperblockClaimChallenged",
    "VerificationGameStarted",
    "SuperblockBattleDecided",
    "SuperblockClaimPending",
    "SuperblockClaimSuccessful",
    "SuperblockClaimFailed",
    "ErrorClaim",
  ];
  await printContractEvents(superblockClaimEvents, superblockClaims);
  console.log("");
}

async function printSuperblockchainBattles({
  battleManager: battleManager,
}: DogethereumSystem) {
  console.log("Battles for superblock claims");
  console.log("---------");

  // idea: merge these into a single list and sort them by tx execution order?
  const superblockBattleEvents = [
    "NewBattle",
    "QueryMerkleRootHashes",
    "RespondMerkleRootHashes",
    "QueryBlockHeader",
    "RespondBlockHeader",
    "RequestScryptHashValidation",
    "ResolvedScryptHashValidation",
    "ChallengerConvicted",
    "SubmitterConvicted",
    "ErrorBattle",
  ];
  await printContractEvents(superblockBattleEvents, battleManager);
  console.log("");
}

async function printUnlockEvent(events: Event[], dogeToken: Contract) {
  if (events.length === 0) {
    console.log("No unlock events.");
    return;
  }

  console.log("Unlock events");

  for (const event of events) {
    const fragment = dogeToken.interface.getEvent(event.eventSignature!);
    const args = enumerateEventArguments(event, fragment);
    const {
      from,
      dogeAddress,
      value,
      operatorFee,
      timestamp,
      selectedUtxos,
      dogeTxFee,
      operatorPublicKeyHash,
    } = await dogeToken.getUnlockPendingInvestorProof(event.args!.id, {
      blockTag: event.blockNumber,
    });
    console.log(`- tx hash: ${event.transactionHash} log index: ${
      event.logIndex
    }
  block number: ${event.blockNumber}
  args:
  - ${args.join(`
    `)}
  unlock info:
  - from: ${from}
    dogecoin address: ${dogeAddress}
    value: ${value}
    operator fee: ${operatorFee}
    timestamp: ${timestamp}
    selectedUtxos: ${selectedUtxos}
    doge tx fee: ${dogeTxFee}
    operator public key hash: ${operatorPublicKeyHash}`);
  }
}

async function showBalance(dogeToken: Contract, address: string) {
  const balance = await dogeToken.callStatic.balanceOf(address);
  console.log(`DogeToken Balance of ${address}: ${balance}`);
}

async function printContractEvents(
  eventNames: string[],
  { contract, name }: DogethereumContract
) {
  console.log(`${name} events`);
  for (const eventName of eventNames) {
    const filter = contract.filters[eventName]();
    const events = await contract.queryFilter(filter, 0, "latest");

    console.log(`- ${eventName}`);
    for (const event of events) {
      const fragment = contract.interface.getEvent(event.eventSignature!);
      const args = enumerateEventArguments(event, fragment);
      console.log(`  - tx hash: ${event.transactionHash} log index: ${
        event.logIndex
      }
    block number: ${event.blockNumber}
    args:
    - ${args.join(`
      `)}`);
    }
  }
}

function enumerateEventArguments(
  event: Event,
  fragment: utils.EventFragment
): string[] {
  if (event.args === undefined) {
    throw new Error("Arguments missing in ${event.event} event.");
  }

  const args = [];
  // Event argument names are present in the `event.args` as custom properties,
  // but they are hard to enumerate. This is why we use the event fragment instead.
  for (const [index, value] of event.args.entries()) {
    args.push(`${fragment.inputs[index].name}: ${value}`);
  }
  return args;
}

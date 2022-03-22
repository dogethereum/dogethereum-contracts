import { task, types } from "hardhat/config";
import { ActionType } from "hardhat/types";
import type { BigNumber, Contract, ContractTransaction, Event, providers } from "ethers";

import { loadDeployment, DogethereumSystem } from "../deploy";

import { Battle, BridgeEvent } from "./battle";
import { accelerateTimeOnNewProposal, delay, generateTaskName, testProcess } from "./common";
import "./mineDogeBlock";
import "./assertTokenStatus";

// TODO: separate this into two modules: one for the status task and another for the challenge task.

/**
 * This enum is meant to be identical to the enum Status found in the DogeSuperblocks contract.
 */
enum Status {
  Uninitialized,
  New,
  InBattle,
  SemiApproved,
  Approved,
  Invalid,
}

/**
 * This enum is meant to be identical to the enum ChallengeState found in the DogeBattleManager contract.
 */
enum ChallengeState {
  /**
   * Unchallenged submission
   */
  Unchallenged,
  /**
   * Claim was challenged
   */
  Challenged,
  /**
   * Challenger expecting block hashes
   */
  QueryMerkleRootHashes,
  /**
   * Block hashes were received and verified
   */
  RespondMerkleRootHashes,
  /**
   * Challenger is requesting block headers
   */
  QueryBlockHeader,
  /**
   * All block headers were received
   */
  RespondBlockHeader,
  VerifyScryptHash,
  RequestScryptVerification,
  PendingScryptVerification,
  /**
   * Pending superblock verification
   */
  PendingVerification,
  /**
   * Superblock verified
   */
  SuperblockVerified, //
  /**
   * Superblock not valid
   */
  SuperblockFailed,
}

interface BattleStatus {
  sessionId: number;
  battle: {
    id: string;
    superblockHash: string;
    submitter: string;
    challenger: string;
    lastActionTimestamp: BigNumber;
    lastActionClaimant: BigNumber;
    lastActionChallenger: BigNumber;
    actionsCounter: BigNumber;
    countBlockHeaderQueries: BigNumber;
    countBlockHeaderResponses: BigNumber;
    pendingScryptHashId: string;
    challengeState: ChallengeState;
  };
}

/**
 * This interface is meant to be identical to the struct SuperblockClaim found in the DogeBattleManager contract.
 */
interface SuperblockClaim {
  /**
   * Superblock Id
   */
  superblockHash: string;
  /**
   * Superblock submitter
   */
  submitter: string;
  /**
   * Superblock creation time
   */
  createdAt: BigNumber;

  /**
   * Index of challenger in current session
   */
  currentChallenger: BigNumber;

  /**
   * Claim timeout
   */
  challengeTimeout: BigNumber;

  /**
   * Challenge session has started
   */
  verificationOngoing: boolean;

  /**
   * If the claim was decided
   */
  decided: boolean;
  /**
   * If superblock is invalid
   */
  invalid: boolean;
}

interface ChallengeTaskArguments {
  advanceBattle: boolean;
  superblockId?: string;
  challenger?: string;
  deposit?: string;
  agentPid?: number;
}

interface StatusTaskArguments {
  superblockId?: string;
  fromBlock?: number;
  toBlock?: number;
}

interface WaitUtxoTaskArguments {
  operatorPublicKeyHash: string;
  utxoLength: number;
}

const STATUS_UNINITIALIZED = 0;

export const STATUS_TASK = generateTaskName("status");
export const CHALLENGE_TASK = generateTaskName("challenge");
export const WAIT_UTXO_TASK = generateTaskName("waitUtxo");

function decodeBattleEvent(battleManager: Contract, event: Event): BridgeEvent {
  if (event.event !== undefined) {
    if (event.args === undefined) throw new Error("Invalid event.");

    return {
      name: event.event,
      args: event.args,
    };
  }

  try {
    const log = battleManager.interface.parseLog(event);
    return {
      name: log.name,
      args: log.args,
    };
  } catch {
    return {
      name: "Unknown",
      args: [],
    };
  }
}

async function challengeNextSuperblock(
  superblocks: Contract,
  superblockClaims: Contract,
  battleManager: Contract,
  challenger: string,
  superblockId?: string,
  deposit?: number | string,
  agentPid?: number
) {
  console.log(`Making a challenge from: ${challenger}`);
  let balance = await superblockClaims.callStatic.getDeposit(challenger);
  if (balance.eq(0)) {
    deposit = deposit ?? 1000;
  }
  if (deposit !== undefined) {
    await superblockClaims.makeDeposit({ value: deposit });
    balance = await superblockClaims.callStatic.getDeposit(challenger);
  }
  console.log(`Deposits: ${balance.toString()}`);

  const bestSuperblockHash: string = await superblocks.getBestSuperblock();
  const bestSuperblock = await superblocks.getSuperblock(bestSuperblockHash);

  const height: number = await superblocks.getSuperblockHeight(bestSuperblockHash);

  console.log("----------");
  console.log(`Last superblock: ${bestSuperblockHash}`);
  console.log(`Height: ${height}`);
  console.log(`Date: ${new Date(bestSuperblock.timestamp * 1000)}`);
  console.log(`Last doge hash: ${bestSuperblock.lastHash}`);
  console.log("----------");

  superblockId = await nextSuperblockEvent(superblocks, bestSuperblockHash, superblockId, agentPid);

  const findEvent = (events: BridgeEvent[], eventName: string) => {
    return events.find(({ name }) => {
      return name === eventName;
    });
  };

  const response: ContractTransaction = await superblockClaims.challengeSuperblock(superblockId);
  const receipt = await response.wait();
  if (receipt.events === undefined) {
    throw new Error("Couldn't find events in the transaction sent.");
  }

  // Only superblockClaims events are decoded,
  // so we need to decode battleManager events here.
  const events = receipt.events.map((event) => decodeBattleEvent(battleManager, event));
  const challengeEvent = findEvent(events, "SuperblockClaimChallenged");
  const newBattleEvent = findEvent(events, "NewBattle");
  if (challengeEvent === undefined) {
    console.log("Failed to challenge next superblock");
  } else {
    if (challengeEvent.args === undefined) {
      throw new Error("Bad challenge event.");
    }

    console.log(`Challenged superblock: ${challengeEvent.args.superblockHash}`);
    const nextSuperblock = await superblocks.getSuperblock(challengeEvent.args.superblockHash);
    if (newBattleEvent !== undefined) {
      console.log("Battle started");
      console.log(`sessionId: ${newBattleEvent.args.sessionId}`);
      console.log(`submitter: ${newBattleEvent.args.submitter}`);
      console.log(`challenger: ${newBattleEvent.args.challenger}`);
    } else {
      console.log("Superblock");
      console.log(`submitter: ${nextSuperblock.submitter}`);
      console.log(`challenger: ${challengeEvent.args.challenger}`);
    }
  }
  console.log("----------");
  return { challengeEvent, newBattleEvent };
}

async function nextSuperblockEvent(
  superblocks: Contract,
  bestSuperblockId: string,
  superblockId?: string,
  agentPid?: number
): Promise<string> {
  if (typeof superblockId === "string") {
    const { status } = await superblocks.superblocks(superblockId);
    if (status !== STATUS_UNINITIALIZED) {
      return superblockId;
    }
  }

  return new Promise((resolve, reject) => {
    const newSuperblockFilter = superblocks.filters.NewSuperblock();
    // TODO: does it make sense to keep waiting after the first event?
    // This assumes that a future superblock hash was predicted
    // which might be indeed the case in a development environment
    // but might overcomplicate this implementation if it isn't used at all.

    // Monitor agent process to avoid waiting indefinitely.
    let intervalToken: NodeJS.Timeout;
    if (agentPid !== undefined) {
      const agentChecker = () => {
        if (!testProcess(agentPid)) {
          superblocks.off(newSuperblockFilter, listener);
          clearInterval(intervalToken);
          reject(new Error("The agent process exited without sending superblocks."));
        }
      };
      intervalToken = setInterval(agentChecker, 300);
    }

    const listener: providers.Listener = (
      newSuperblockId
      // submitter,
      // event
    ) => {
      if (newSuperblockId === bestSuperblockId) return;
      if (superblockId === undefined || newSuperblockId === superblockId) {
        superblocks.off(newSuperblockFilter, listener);
        if (intervalToken !== undefined) {
          clearInterval(intervalToken);
        }
        resolve(newSuperblockId);
      }
    };
    superblocks.on(newSuperblockFilter, listener);
  });
}

const challengeCommand: ActionType<ChallengeTaskArguments> = async function (
  { advanceBattle, superblockId, challenger, deposit, agentPid },
  hre
) {
  console.log("challenge the next superblock");

  let signer;
  if (challenger === undefined) {
    signer = (await hre.ethers.getSigners())[0];
  } else {
    signer = await hre.ethers.getSigner(challenger);
  }

  const deployment = await loadDeployment(hre);
  const superblocks = deployment.superblocks.contract;
  const superblockClaims = deployment.superblockClaims.contract.connect(signer);
  const battleManager = deployment.battleManager.contract.connect(signer);

  const { newBattleEvent } = await challengeNextSuperblock(
    superblocks,
    superblockClaims,
    battleManager,
    signer.address,
    superblockId,
    deposit,
    agentPid
  );

  console.log("challenge the next superblock complete");

  if (advanceBattle && newBattleEvent !== undefined) {
    const battle = await Battle.createFromEvent(battleManager, newBattleEvent);
    console.log("Querying block hashes...");
    let receipt = await battle.queryMerkleRootHashes();
    await battle.nextResponse(receipt.blockNumber + 1);
    const hashes = await battle.getBlockHashes();
    const firstHashes = hashes.slice(0, 5);
    for (const hash of firstHashes) {
      console.log(`Querying block header ${hash}...`);
      receipt = await battle.queryBlockHeader(hash);
      await battle.nextResponse(receipt.blockNumber + 1);
    }

    console.log("Finished querying! Challenge abandoned.");
  }
};

task(CHALLENGE_TASK, "Submit a challenge to a superblock")
  .addOptionalParam(
    "advanceBattle",
    "Queries the first five hashes in the battle, then abandons the battle.",
    false,
    types.boolean
  )
  .addOptionalParam(
    "superblockId",
    "Superblock ID to challenge. If the superblock was not submitted yet it will wait for it. When this option is not specified, the next superblock is challenged instead.",
    undefined,
    types.string
  )
  .addOptionalParam(
    "challenger",
    "Address of the account used to send the challenge. When not specified it will use the first account available in the runtime environment.",
    undefined,
    types.string
  )
  .addOptionalParam(
    "deposit",
    "The amount of ether deposited in the contract in wei. If the balance is zero and no deposit is specified it will try to deposit 1000 wei.",
    undefined,
    types.string
  )
  .addOptionalParam(
    "agentPid",
    `The agent PID. When given, the task will monitor the process to see if it's still alive while waiting for the new superblock proposal.
If the superblock is not proposed by the time the agent is closed, the task fails with an exception.`,
    undefined,
    types.int
  )
  .setAction(challengeCommand);

function statusToText(status: Status) {
  if (typeof Status[status] !== "undefined") {
    return Status[status];
  }
  throw new Error("Unknown superblock status");
}

function challengeStateToText(state: ChallengeState) {
  const challengeStates: { [s in ChallengeState]: string } = {
    [ChallengeState.Unchallenged]: "Unchallenged",
    [ChallengeState.Challenged]: "Challenged",
    [ChallengeState.QueryMerkleRootHashes]: "Merkle root hashes queried",
    [ChallengeState.RespondMerkleRootHashes]: "Merkle root hashes replied",
    [ChallengeState.QueryBlockHeader]: "Block header queried",
    [ChallengeState.RespondBlockHeader]: "Block header replied",
    [ChallengeState.VerifyScryptHash]: "Waiting scrypt hash request",
    [ChallengeState.RequestScryptVerification]: "Scrypt hash verification requested",
    [ChallengeState.PendingScryptVerification]: "Scrypt hash Verification pending",
    [ChallengeState.PendingVerification]: "Superblock verification pending",
    [ChallengeState.SuperblockVerified]: "Superblock verified",
    [ChallengeState.SuperblockFailed]: "Superblock failed",
  };
  if (typeof ChallengeState[state] !== "undefined") {
    return challengeStates[state];
  }
  return `--Invalid state (${state})--`;
}

async function displaySuperblocksStatus(
  dogethereum: DogethereumSystem,
  fromBlock: string | number = 0,
  toBlock: string | number = "latest"
) {
  const newSuperblockEventsFilter = dogethereum.superblocks.contract.filters.NewSuperblock();
  const newSuperblockEvents = await dogethereum.superblocks.contract.queryFilter(
    newSuperblockEventsFilter,
    fromBlock,
    toBlock
  );
  for (const [index, event] of newSuperblockEvents.entries()) {
    if (event.args === undefined) {
      throw new Error("Missing arguments to NewSuperblock event.");
    }
    const [superblockId] = event.args;
    if (index > 0) {
      console.log("----------");
    }
    await displaySuperblock(dogethereum, superblockId);
  }
}

async function getBattleStatus(
  {
    battleManager: { contract: battleManager },
    superblockClaims: { contract: superblockClaims },
  }: DogethereumSystem,
  superblockHash: string,
  challenger: string
): Promise<BattleStatus> {
  const sessionId = await superblockClaims.getSession(superblockHash, challenger);
  const {
    id,
    submitter,
    lastActionTimestamp,
    lastActionClaimant,
    lastActionChallenger,
    actionsCounter,
    countBlockHeaderQueries,
    countBlockHeaderResponses,
    pendingScryptHashId,
    challengeState,
  } = await battleManager.sessions(sessionId);
  return {
    sessionId,
    battle: {
      id,
      superblockHash,
      submitter,
      challenger,
      lastActionTimestamp,
      lastActionClaimant,
      lastActionChallenger,
      actionsCounter,
      countBlockHeaderQueries,
      countBlockHeaderResponses,
      pendingScryptHashId,
      challengeState,
    },
  };
}

function getBattles(dogethereum: DogethereumSystem, superblockHash: string, challengers: string[]) {
  return Promise.all(
    challengers.map((challenger) => getBattleStatus(dogethereum, superblockHash, challenger))
  );
}

async function getClaimInfo(
  { superblockClaims: { contract: superblockClaims } }: DogethereumSystem,
  superblockHash: string
): Promise<SuperblockClaim> {
  const {
    submitter,
    createdAt,
    currentChallenger,
    challengeTimeout,
    verificationOngoing,
    decided,
    invalid,
  } = await superblockClaims.claims(superblockHash);
  return {
    superblockHash,
    submitter,
    createdAt,
    currentChallenger,
    challengeTimeout,
    verificationOngoing,
    decided,
    invalid,
  };
}

function displayBattle(battle: BattleStatus["battle"]) {
  console.log(
    `        Last action timestamp: ${new Date(battle.lastActionTimestamp.mul(1000).toString())}`
  );
  console.log(
    `        Last action: ${
      battle.lastActionClaimant.gt(battle.lastActionChallenger) ? "claimant" : "challenger"
    }`
  );
  console.log(`        State: ${challengeStateToText(battle.challengeState)}`);
}

async function displaySuperblock(dogethereum: DogethereumSystem, superblockHash: string) {
  const { timestamp, submitter, status } = await dogethereum.superblocks.contract.getSuperblock(
    superblockHash
  );
  const challengers: string[] = await dogethereum.superblockClaims.contract.getClaimChallengers(
    superblockHash
  );
  const claim = await getClaimInfo(dogethereum, superblockHash);
  const battles = await getBattles(dogethereum, superblockHash, challengers);
  console.log(`Superblock: ${superblockHash}`);
  console.log(`Submitter: ${submitter}`);
  console.log(`Last block Timestamp: ${new Date(timestamp.mul(1000).toString())}`);
  console.log(`Status: ${statusToText(status)}`);
  console.log(`Superblock submitted: ${new Date(claim.createdAt.mul(1000).toString())}`);
  console.log(`Challengers: ${challengers.length}`);
  console.log(`Challengers Timeout: ${new Date(claim.challengeTimeout.mul(1000).toString())}`);
  if (claim.decided) {
    console.log(`Claim decided: ${claim.invalid ? "invalid" : "valid"}`);
  } else {
    console.log(`Verification: ${claim.verificationOngoing ? "ongoing" : "paused/stopped"}`);
  }
  if (challengers.length > 0) {
    console.log(`Current challenger: ${claim.currentChallenger}`);
    console.log(`Challengers: ${challengers.length}`);
    challengers.forEach((challenger, idx) => {
      console.log("    ----------");
      console.log(`    Challenger: ${challenger}`);
      console.log(`    Battle session: ${battles[idx].sessionId}`);
      if (claim.currentChallenger.eq(idx + 1)) {
        if (claim.decided) {
          console.log(`    Challenge state: ${claim.invalid ? "succeeded" : "failed"}`);
        } else if (claim.verificationOngoing) {
          displayBattle(battles[idx].battle);
          console.log(
            `    Challenge state: ${challengeStateToText(battles[idx].battle.challengeState)}`
          );
        } else {
          console.log("    Challenge state: waiting");
        }
      } else if (claim.currentChallenger.gt(idx + 1)) {
        console.log("    Challenge state: failed");
      } else {
        console.log("    Challenge state: pending");
      }
    });
  }
}

const statusCommand: ActionType<StatusTaskArguments> = async function (
  { superblockId, fromBlock, toBlock },
  hre
) {
  console.log("status superblocks");
  console.log("----------");

  const dogethereum = await loadDeployment(hre);
  if (typeof superblockId === "string") {
    await displaySuperblock(dogethereum, superblockId);
  } else {
    await displaySuperblocksStatus(dogethereum, fromBlock, toBlock);
  }
  console.log("----------");
  console.log("status superblocks complete");
};

task(
  STATUS_TASK,
  "Show the status of a paritcular superblock or the status of superblocks in a given range of ethereum blocks."
)
  .addOptionalParam(
    "superblockId",
    "Id (i.e. hash) of the superblock that should be queried. Specifying this option overrides fromBlock and toBlock parameters.",
    undefined,
    types.string
  )
  .addOptionalParam("fromBlock", "Lower bound of the interval of blocks to query.", 0, types.string)
  .addOptionalParam(
    "toBlock",
    "Upper bound of the interval of blocks to query.",
    "latest",
    types.string
  )
  .setAction(statusCommand);

const waitUtxoCommand: ActionType<WaitUtxoTaskArguments> = async function (
  { operatorPublicKeyHash, utxoLength: expectedUtxoLength },
  hre
) {
  const {
    dogeToken: { contract: dogeToken },
    superblockClaims: { contract: superblockClaims },
    superblocks: { contract: superblocks },
  } = await loadDeployment(hre);
  let utxosLength = await dogeToken.getUtxosLength(operatorPublicKeyHash);
  console.log(`Utxo length of operator ${operatorPublicKeyHash} : ${utxosLength}`);

  const superblockTimeout = (await superblockClaims.superblockTimeout()).toNumber();
  let blockNumber = 0;

  while (utxosLength < expectedUtxoLength) {
    await delay(500);
    blockNumber = await accelerateTimeOnNewProposal(
      hre,
      superblocks,
      superblockTimeout,
      blockNumber
    );
    utxosLength = await dogeToken.getUtxosLength(operatorPublicKeyHash);
  }
  console.log(`Utxo length of operator ${operatorPublicKeyHash} : ${utxosLength}`);
};

task(WAIT_UTXO_TASK, "Wait until a particular operator has a specific amount of UTXOs.")
  .addParam(
    "operatorPublicKeyHash",
    "Hash of the public key of the operator that should be monitored",
    undefined,
    types.string
  )
  .addParam("utxoLength", "Minimum amount of UTXOs expected.", undefined, types.int)
  .setAction(waitUtxoCommand);

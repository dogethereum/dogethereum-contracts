import { task, types } from "hardhat/config";
import { ActionType } from "hardhat/types";
import { loadDeployment, DogethereumSystem } from "../deploy";
import type {
  BigNumber,
  Contract,
  ContractTransaction,
  Event,
  providers,
} from "ethers";

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
  superblockId?: string;
  challenger?: string;
  deposit?: string;
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

const DOGETHEREUM_SUPERCLI = "dogethereum";
const STATUS_TASK = `${DOGETHEREUM_SUPERCLI}.status`;
const CHALLENGE_TASK = `${DOGETHEREUM_SUPERCLI}.challenge`;
const WAIT_UTXO_TASK = `${DOGETHEREUM_SUPERCLI}.waitUtxo`;

async function challengeNextSuperblock(
  superblocks: Contract,
  superblockClaims: Contract,
  challenger: string,
  superblockId?: string,
  deposit?: number | string
) {
  console.log(`Making a challenge from: ${challenger}`);
  let balance = await superblockClaims.getDeposit(challenger);
  if (balance.eq(0)) {
    deposit = deposit ?? 1000;
  }
  if (deposit !== undefined) {
    await superblockClaims.makeDeposit({ value: deposit });
    balance = await superblockClaims.getDeposit(challenger);
  }
  console.log(`Deposits: ${balance.toString()}`);

  const bestSuperblockHash = await superblocks.getBestSuperblock();
  const bestSuperblock = await superblocks.getSuperblock(bestSuperblockHash);

  const height = await superblocks.getSuperblockHeight(bestSuperblockHash);

  console.log("----------");
  console.log(`Last superblock: ${bestSuperblockHash}`);
  console.log(`Height: ${height}`);
  console.log(`Date: ${new Date(bestSuperblock[2] * 1000)}`);
  console.log(`Last doge hash: ${bestSuperblock[4]}`);
  console.log("----------");

  superblockId = await nextSuperblockEvent(superblocks, superblockId);

  const findEvent = (events: Event[], eventName: string) => {
    return events.find(({ event }) => {
      return event === eventName;
    });
  };

  const response: ContractTransaction = await superblockClaims.challengeSuperblock(
    superblockId
  );
  const receipt = await response.wait();
  if (receipt.events === undefined) {
    throw new Error("Couldn't find events in the transaction sent.");
  }
  const challengeEvent = findEvent(receipt.events, "SuperblockClaimChallenged");
  const newBattleEvent = findEvent(receipt.events, "NewBattle");
  if (challengeEvent === undefined) {
    console.log("Failed to challenge next superblock");
  } else {
    console.log(
      `Challenged superblock: ${challengeEvent.args!.superblockHash}`
    );
    const nextSuperblock = await superblocks.getSuperblock(
      challengeEvent.args!.superblockHash
    );
    if (newBattleEvent !== undefined) {
      console.log("Battle started");
      console.log(`sessionId: ${newBattleEvent.args!.sessionId}`);
      console.log(`submitter: ${newBattleEvent.args!.submitter}`);
      console.log(`challenger: ${newBattleEvent.args!.challenger}`);
    } else {
      console.log("Superblock");
      console.log(`submitter: ${nextSuperblock[7]}`);
      console.log(`challenger: ${challengeEvent.args!.challenger}`);
    }
  }
  console.log("----------");
}

async function nextSuperblockEvent(
  superblocks: Contract,
  superblockId?: string
): Promise<string> {
  if (typeof superblockId === "string") {
    const superblock = await superblocks.getSuperblock(superblockId);
    if (superblock[8] !== STATUS_UNINITIALIZED) {
      return superblockId;
    }
  }

  return new Promise((resolve) => {
    const newSuperblockFilter = superblocks.filters.NewSuperblock();
    // TODO: does it make sense to keep waiting after the first event?
    // This assumes that a future superblock hash was predicted
    // which might be indeed the case in a development environment
    // but might overcomplicate this implementation if it isn't used at all.
    const listener: providers.Listener = (
      newSuperblockId
      // submitter,
      // event
    ) => {
      if (superblockId === undefined || newSuperblockId === superblockId) {
        superblocks.off(newSuperblockFilter, listener);
        resolve(newSuperblockId);
      }
    };
    superblocks.on(newSuperblockFilter, listener);
  });
}

const challengeCommand: ActionType<ChallengeTaskArguments> = async function (
  { superblockId, challenger, deposit },
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

  await challengeNextSuperblock(
    superblocks,
    superblockClaims,
    signer.address,
    superblockId,
    deposit
  );
  console.log("challenge the next superblock complete");
};

task(CHALLENGE_TASK, "Submit a challenge to a superblock")
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
    [ChallengeState.RequestScryptVerification]:
      "Scrypt hash verification requested",
    [ChallengeState.PendingScryptVerification]:
      "Scrypt hash Verification pending",
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
  const sessionId = await superblockClaims.getSession(
    superblockHash,
    challenger
  );
  const [
    id,
    ,
    submitter,
    ,
    lastActionTimestamp,
    lastActionClaimant,
    lastActionChallenger,
    actionsCounter,
    countBlockHeaderQueries,
    countBlockHeaderResponses,
    pendingScryptHashId,
    challengeState,
  ] = await battleManager.sessions(sessionId);
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

function getBattles(
  dogethereum: DogethereumSystem,
  superblockHash: string,
  challengers: string[]
) {
  return Promise.all(
    challengers.map((challenger) =>
      getBattleStatus(dogethereum, superblockHash, challenger)
    )
  );
}

async function getClaimInfo(
  { superblockClaims: { contract: superblockClaims } }: DogethereumSystem,
  superblockHash: string
): Promise<SuperblockClaim> {
  const [
    ,
    submitter,
    createdAt,
    currentChallenger,
    challengeTimeout,
    verificationOngoing,
    decided,
    invalid,
  ] = await superblockClaims.claims(superblockHash);
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
    `        Last action timestamp: ${new Date(
      battle.lastActionTimestamp.mul(1000).toString()
    )}`
  );
  console.log(
    `        Last action: ${
      battle.lastActionClaimant.gt(battle.lastActionChallenger)
        ? "claimant"
        : "challenger"
    }`
  );
  console.log(`        State: ${challengeStateToText(battle.challengeState)}`);
}

async function displaySuperblock(
  dogethereum: DogethereumSystem,
  superblockHash: string
) {
  const {
    timestamp,
    submitter,
    status,
  } = await dogethereum.superblocks.contract.getSuperblock(superblockHash);
  const challengers: string[] = await dogethereum.superblockClaims.contract.getClaimChallengers(
    superblockHash
  );
  const claim = await getClaimInfo(dogethereum, superblockHash);
  const battles = await getBattles(dogethereum, superblockHash, challengers);
  console.log(`Superblock: ${superblockHash}`);
  console.log(`Submitter: ${submitter}`);
  console.log(
    `Last block Timestamp: ${new Date(timestamp.mul(1000).toString())}`
  );
  console.log(`Status: ${statusToText(status)}`);
  console.log(
    `Superblock submitted: ${new Date(claim.createdAt.mul(1000).toString())}`
  );
  console.log(`Challengers: ${challengers.length}`);
  console.log(
    `Challengers Timeout: ${new Date(
      claim.challengeTimeout.mul(1000).toString()
    )}`
  );
  if (claim.decided) {
    console.log(`Claim decided: ${claim.invalid ? "invalid" : "valid"}`);
  } else {
    console.log(
      `Verification: ${
        claim.verificationOngoing ? "ongoing" : "paused/stopped"
      }`
    );
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
          console.log(
            `    Challenge state: ${claim.invalid ? "succeeded" : "failed"}`
          );
        } else if (claim.verificationOngoing) {
          displayBattle(battles[idx].battle);
          console.log(
            `    Challenge state: ${challengeStateToText(
              battles[idx].battle.challengeState
            )}`
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
  .addOptionalParam(
    "fromBlock",
    "Lower bound of the interval of blocks to query.",
    0,
    types.string
  )
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
  } = await loadDeployment(hre);
  let utxosLength = await dogeToken.getUtxosLength(operatorPublicKeyHash);
  console.log(
    `Utxo length of operator ${operatorPublicKeyHash} : ${utxosLength}`
  );

  while (utxosLength < expectedUtxoLength) {
    await delay(2000);
    utxosLength = await dogeToken.getUtxosLength(operatorPublicKeyHash);
  }
  console.log(
    `Utxo length of operator ${operatorPublicKeyHash} : ${utxosLength}`
  );
};

function delay(milliseconds: number) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

task(
  WAIT_UTXO_TASK,
  "Wait until a particular operator has a specific amount of UTXOs."
)
  .addParam(
    "operatorPublicKeyHash",
    "Hash of the public key of the operator that should be monitored",
    undefined,
    types.string
  )
  .addParam(
    "utxoLength",
    "Minimum amount of UTXOs expected.",
    undefined,
    types.int
  )
  .setAction(waitUtxoCommand);

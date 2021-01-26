const DogeSuperblocks = artifacts.require("DogeSuperblocks");
const DogeClaimManager = artifacts.require("DogeClaimManager");
const DogeBattleManager = artifacts.require("DogeBattleManager");
const BigNumber = require('bignumber.js');

async function challengeNextSuperblock(from, toChallenge, deposit) {
  try {
    const sb = await DogeSuperblocks.deployed();
    const cm = await DogeClaimManager.deployed();

    let challenger;
    if (typeof from === 'string' && from.startsWith('0x')) {
      challenger = from;
    } else {
      challenger = web3.eth.accounts[0];
    }

    console.log(`Making a challenge from: ${challenger}`);
    let balance = await cm.getDeposit(challenger);
    if (typeof deposit === 'string' || balance.toNumber() === 0) {
      const amount = typeof deposit === 'string' ? BigNumber(deposit) : 1000;
      await cm.makeDeposit({ from: challenger, value: amount });
      balance = await cm.getDeposit(challenger);
    }
    console.log(`Deposits: ${balance.toNumber()}`);

    const nextSuperblockEvent = function (toChallenge) {
      return new Promise(async (resolve, reject) => {
        if (typeof toChallenge === 'string') {
          const superblock = await sb.getSuperblock(toChallenge);
          if (superblock[8].toNumber() !== 0) {
            resolve({
              superblockHash: toChallenge,
            });
            return;
          }
        }
        const newSuperblockEvents = sb.NewSuperblock();
        newSuperblockEvents.watch((err, result) => {
          if (err) {
            newSuperblockEvents.stopWatching();
            return reject(err);
          }

          if (typeof toChallenge !== 'string' ||
            (typeof toChallenge === 'string' && toChallenge === result.args.superblockHash)) {
            newSuperblockEvents.stopWatching();
            resolve({
              superblockHash: result.args.superblockHash,
            });
          }
        });
      });
    }

    const bestSuperblockHash = await sb.getBestSuperblock();
    const bestSuperblock = await sb.getSuperblock(bestSuperblockHash);

    const height = await sb.getSuperblockHeight(bestSuperblockHash);

    console.log('----------');
    console.log(`Last superblock: ${bestSuperblockHash}`);
    console.log(`Height: ${height}`);
    console.log(`Date: ${new Date(bestSuperblock[2] * 1000)}`);
    console.log(`Last doge hash: ${bestSuperblock[4]}`);
    console.log('----------');

    const nextSuperblock = await nextSuperblockEvent(toChallenge);
    const nextSuperblockHash = nextSuperblock.superblockHash;

    const findEvent = (logs, eventName) => {
      return logs.find((log) => {
        return log.event === eventName;
      });
    };

    const result = await cm.challengeSuperblock(nextSuperblockHash, { from: challenger });
    const challengeEvent = findEvent(result.logs, 'SuperblockClaimChallenged');
    const newBattleEvent = findEvent(result.logs, 'NewBattle');
    if (!challengeEvent) {
      console.log('Failed to challenge next superblock');
    } else {
      console.log(`Challenged superblock: ${challengeEvent.args.superblockHash}`);
      const nextSuperblock = await sb.getSuperblock(challengeEvent.args.superblockHash);
      if (newBattleEvent) {
        console.log('Battle started');
        console.log(`sessionId: ${newBattleEvent.args.sessionId}`);
        console.log(`submitter: ${newBattleEvent.args.submitter}`);
        console.log(`challenger: ${newBattleEvent.args.challenger}`);
      } else {
        console.log('Superblock');
        console.log(`submitter: ${nextSuperblock[7]}`);
        console.log(`challenger: ${challengeEvent.args.challenger}`);
      }
    }
    console.log('----------');
  } catch (err) {
    console.log(err);
  }
}

function findCommand(params) {
  const index = params.findIndex((param, idx) => {
    return param.indexOf('superblock-cli.js') >= 0;
  });
  if (index >= 0 && index+1 < params.length) {
    return {
      command: params[index + 1],
      params: params.slice(index + 2),
    };
  } else {
    return {};
  }
}

function findParam(params, paranName) {
  const index = params.findIndex((param, idx) => {
    return param === paranName;
  });
  return (index >= 0 && index+1 < params.length) ? params[index + 1] : null;
}

async function challengeCommand(params) {
  console.log("challenge the next superblock");
  const challenger = findParam(params, '--from');
  const superblock  = findParam(params, '--superblock');
  const amount  = findParam(params, '--deposit');
  await challengeNextSuperblock(challenger, superblock, amount);
  console.log("challenge the next superblock complete");
}

function statusToText(status) {
  const statuses = {
    0: 'Unitialized',
    1: 'New',
    2: 'InBattle',
    3: 'SemiApproved',
    4: 'Approved',
    5: 'Invalid',
  }
  if (typeof statuses[status] !== 'undefined') {
    return statuses[status];
  }
  return '--Status error--';
}

function challengeStateToText(state) {
  const challengeStates = {
    0: 'Unchallenged',
    1: 'Challenged',
    2: 'Merkle root hashes queried',
    3: 'Merkle root hashes replied',
    4: 'Block header queried',
    5: 'Block header replied',
    6: 'Waiting scrypt hash request',
    7: 'Scrypt hash verification requested',
    8: 'Scrypt hash Verification pending',
    9: 'Superblock verification pending',
    10: 'Superblock verified',
    11: 'Superblock failed',
  };
  if (typeof challengeStates[state] !== 'undefined') {
    return challengeStates[state];
  }
  return `--Invalid state (${state})--`;
}

async function displaySuperblocksStatus({ superblockHash, fromBlock, toBlock }) {
  try {
    const sb = await DogeSuperblocks.deployed();
    const cm = await DogeClaimManager.deployed();
    const bm = await DogeBattleManager.deployed();

    const getBattleStatus = async (superblockHash, challenger) => {
      const sessionId = await cm.getSession(superblockHash, challenger);
      const [
        id,
        superblockHash2,
        submitter,
        challenger2,
        lastActionTimestamp,
        lastActionClaimant,
        lastActionChallenger,
        actionsCounter,
        countBlockHeaderQueries,
        countBlockHeaderResponses,
        pendingScryptHashId,
        challengeState,
      ] = await bm.sessions(sessionId);
      return {
        sessionId,
        battle: {
          id,
          superblockHash: superblockHash2,
          submitter,
          challenger: challenger2,
          lastActionTimestamp,
          lastActionClaimant,
          lastActionChallenger,
          actionsCounter,
          countBlockHeaderQueries,
          countBlockHeaderResponses,
          pendingScryptHashId,
          challengeState,
        },
      }
    };

    const getBattles = async (superblockHash, challengers) => {
      return Promise.all(challengers.map((challenger) => {
        return getBattleStatus(superblockHash, challenger);
      }));
    };

    const getClaimInfo = async (superblockHash) => {
      const [
        superblockHash2,
        submitter,
        createdAt,
        currentChallenger,
        challengeTimeout,
        verificationOngoing,
        decided,
        invalid,
      ] = await cm.claims(superblockHash);
      return {
        superblockHash: superblockHash2,
        submitter,
        createdAt,
        currentChallenger,
        challengeTimeout,
        verificationOngoing,
        decided,
        invalid,
      };
    };

    const displayBattle = (battle) => {
      console.log(`        Last action timestamp: ${new Date(battle.lastActionTimestamp * 1000)}`);
      console.log(`        Last action: ${parseInt(battle.lastActionClaimant) > parseInt(battle.lastActionChallenger) ? 'claimant' : 'challenger'}`);
      console.log(`        State: ${challengeStateToText(battle.challengeState)}`);
    };

    const displaySuperblock = async (superblockHash) => {
      const [
        blocksMerkleRoot,
        accumulatedWork,
        timestamp,
        prevTimestamp,
        lastHash,
        lastBits,
        parentId,
        submitter,
        status,
      ] = await sb.getSuperblock(superblockHash);
      const challengers = await cm.getClaimChallengers(superblockHash);
      const claim = await getClaimInfo(superblockHash);
      const battles = await getBattles(superblockHash, challengers);
      console.log(`Superblock: ${superblockHash}`);
      console.log(`Submitter: ${submitter}`);
      // console.log(`Block: ${blockNumber}, hash ${blockHash}`);
      console.log(`Last block Timestamp: ${new Date(timestamp * 1000)}`);
      console.log(`Status: ${statusToText(status)}`);
      console.log(`Superblock submitted: ${new Date(claim.createdAt * 1000)}`);
      console.log(`Challengers: ${challengers.length}`);
      console.log(`Challengers Timeout: ${new Date(claim.challengeTimeout * 1000)}`);
      if (claim.decided) {
        console.log(`Claim decided: ${claim.invalid ? 'invalid' : 'valid'}`);
      } else {
        console.log(`Verification: ${claim.verificationOngoing ? 'ongoing' : 'paused/stopped'}`);
      }
      if (challengers.length > 0) {
        console.log(`Current challenger: ${claim.currentChallenger}`);
        console.log(`Challengers: ${challengers.length}`);
        challengers.forEach((challenger, idx) => {
          console.log('    ----------');
          console.log(`    Challenger: ${challenger}`);
          console.log(`    Battle session: ${battles[idx].sessionId}`);
          if (idx + 1 == claim.currentChallenger) {
            if (claim.decided) {
              console.log(`    Challenge state: ${claim.invalid ? 'succeeded' : 'failed'}`);
            } else if (claim.verificationOngoing) {
              displayBattle(battles[idx].battle);
              console.log(`    Challenge state: ${challengeStateToText(battles[idx].battle.challengeState)}`);
            } else {
              console.log('    Challenge state: waiting');
            }
          } else if (idx + 1 < claim.currentChallenger) {
            console.log('    Challenge state: failed');
          } else {
            console.log('    Challenge state: pending');
          }
        });
      }
    }

    if (typeof superblockHash === 'string') {
      await displaySuperblock(superblockHash);
    } else {
      const newSuperblockEvents = sb.NewSuperblock({}, { fromBlock, toBlock });
      await new Promise((resolve, reject) => {
        newSuperblockEvents.get(async (err, newSuperblocks) => {
          if (err) {
            reject(err);
            return;
          }
          await newSuperblocks.reduce(async (result, newSuperblock) => {
            const idx = await result;
            const { superblockHash } = newSuperblock.args;
            if (idx > 0) { console.log('----------'); }
            await displaySuperblock(superblockHash);
            return idx + 1;
          }, Promise.resolve(0));
          resolve();
        });
      });
    }
  } catch (err) {
    console.log(err);
  }
}

async function statusCommand(params) {
  console.log("status superblocks");
  console.log('----------');
  const fromBlock = findParam(params, '--fromBlock');
  const toBlock  = findParam(params, '--toBlock');
  const superblockHash  = findParam(params, '--superblock');
  if (typeof superblockHash === 'string') {
    await displaySuperblocksStatus({ superblockHash })
  } else {
    await displaySuperblocksStatus({ fromBlock: fromBlock || 0, toBlock: toBlock || 'latest' });
  }
  console.log('----------');
  console.log("status superblocks complete");
}

module.exports = async function(callback) {
  try {
    const { command, params } = findCommand(process.argv);
    if (command === 'challenge') {
      await challengeCommand(params);
    } else if (command === 'status') {
      await statusCommand(params);
    }
  } catch (err) {
    console.log(err);
  }
  callback();
}

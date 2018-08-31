const DogeSuperblocks = artifacts.require("DogeSuperblocks");
const DogeClaimManager = artifacts.require("DogeClaimManager");


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
      const amount = typeof deposit === 'string' ? web3.toBigNumber(deposit) : 1000;
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
              superblockId: toChallenge,
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
            (typeof toChallenge === 'string' && toChallenge === result.args.superblockId)) {
            newSuperblockEvents.stopWatching();
            resolve({
              superblockId: result.args.superblockId,
            });
          }
        });
      });
    }

    const bestSuperblockId = await sb.getBestSuperblock();
    const bestSuperblock = await sb.getSuperblock(bestSuperblockId);

    const height = await sb.getSuperblockHeight(bestSuperblockId);

    console.log('----------');
    console.log(`Last superblock: ${bestSuperblockId}`);
    console.log(`Height: ${height}`);
    console.log(`Date: ${new Date(bestSuperblock[2] * 1000)}`);
    console.log(`Last doge hash: ${bestSuperblock[4]}`);
    console.log('----------');

    const nextSuperblock = await nextSuperblockEvent(toChallenge);
    const nextSuperblockId = nextSuperblock.superblockId;

    const findEvent = (logs, eventName) => {
      return logs.find((log) => {
        return log.event === eventName;
      });
    };

    const result = await cm.challengeSuperblock(nextSuperblockId, { from: challenger });
    const challengeEvent = findEvent(result.logs, 'SuperblockClaimChallenged');
    const newBattleEvent = findEvent(result.logs, 'NewBattle');
    if (!challengeEvent) {
      console.log('Failed to challenge next superblock');
    } else {
      console.log(`Challenged superblock: ${challengeEvent.args.claimId}`);
      const nextSuperblock = await sb.getSuperblock(challengeEvent.args.claimId);
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

async function displaySuperblocksStatus(fromBlock, toBlock) {
  try {
    const sb = await DogeSuperblocks.deployed();
    const cm = await DogeClaimManager.deployed();
    const getBattleStatus = async (superblockId, challenger) => {
      const sessionId = await cm.getSession(superblockId, challenger);
      const battle = await cm.sessions(sessionId);
      return {
        sessionId,
        battle,
      }
    };
    const getBattles = async (superblockId, challengers) => {
      return Promise.all(challengers.map((challenger) => {
        return getBattleStatus(superblockId, challenger);
      }));
    };
    const newSuperblockEvents = sb.NewSuperblock({}, { fromBlock, toBlock });
    await new Promise((resolve, reject) => {
      newSuperblockEvents.get(async (err, newSuperblocks) => {
        if (err) {
          reject(err);
          return;
        }
        await newSuperblocks.reduce(async (result, newSuperblock) => {
          const idx = await result;
          const { superblockId, who: submitter } = newSuperblock.args;
          const { blockNumber, blockHash, } = newSuperblock;
          const [
            blocksMerkleRoot,
            accumulatedWork,
            timestamp,
            prevTimestamp,
            lastHash,
            lastBits,
            parentId,
            ,
            status,
          ] = await sb.getSuperblock(superblockId);
          const challengers = await cm.getClaimChallengers(superblockId);
          const battles = await getBattles(superblockId, challengers);
          if (idx > 0) { console.log('-------'); }
          console.log(`Superblock: ${superblockId}`);
          console.log(`Submitter: ${submitter}`);
          console.log(`Block: ${blockNumber}, hash ${blockHash}`);
          console.log(`Timestamp: ${new Date(timestamp * 1000)}`);
          console.log(`Status: ${statusToText(status)}`);
          if (challengers.length > 0) {
            console.log(`    Challengers: ${challengers.length}`);
            challengers.forEach((challenger, idx) => {
              console.log(`    Challenger: ${challenger}`);
              console.log(`    Session: ${battles[idx].sessionId}`);
              // console.log(`    Session: ${battles[idx].battle}`);
            });
          }
          return idx + 1;
        }, Promise.resolve(0));
        resolve();
      });
    });
  } catch (err) {
    console.log(err);
  }
}

async function statusCommand(params) {
  console.log("status superblocks");
  const fromBlock = findParam(params, '--fromBlock');
  const toBlock  = findParam(params, '--toBlock');
  await displaySuperblocksStatus(fromBlock || 0, toBlock || 'latest');
  console.log("status superblocks complete");
}

module.exports = async function(callback) {
  const { command, params } = findCommand(process.argv);
  if (command === 'challenge') {
    await challengeCommand(params);
  } else if (command === 'status') {
    await statusCommand(params);
  }
  callback();
}

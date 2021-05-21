import type { Contract, Event } from "ethers";
import type { HardhatRuntimeEnvironment } from "hardhat/types";
import type { DogethereumSystem } from "../deploy";

import { getWalletFor, Role } from "./signers";

export async function printStatus(
  hre: HardhatRuntimeEnvironment,
  deployment: DogethereumSystem
) {
  const superblocks = deployment.superblocks.contract;
  const claimManager = deployment.claimManager.contract;
  console.log("Superblocks");
  console.log("---------");
  const bestSuperblockHash = await superblocks.callStatic.getBestSuperblock();
  console.log("Best superblock hash: " + bestSuperblockHash.toString(16));
  const bestSuperblockHeight = await superblocks.callStatic.getSuperblockHeight(
    bestSuperblockHash
  );
  console.log("Best superblock height: " + bestSuperblockHeight);
  const lastHash = await superblocks.callStatic.getSuperblockLastHash(
    bestSuperblockHash
  );
  console.log("lastHash: " + lastHash);
  const indexNextSuperblock = await superblocks.callStatic.getIndexNextSuperblock();
  console.log("indexNextSuperblock: " + indexNextSuperblock);
  const newSuperblockEventTimestamp = await claimManager.callStatic.getNewSuperblockEventTimestamp(
    bestSuperblockHash
  );
  console.log("newSuperblockEventTimestamp: " + newSuperblockEventTimestamp);
  console.log("");

  console.log("DogeToken");
  console.log("---------");
  const dogeToken = deployment.dogeToken.contract;

  await showBalance(dogeToken, "0x92ecc1ba4ea10f681dcf35c02f583e59d2b99b4b");

  const userWallet = getWalletFor(Role.User);
  await showBalance(dogeToken, userWallet.address);

  await showBalance(dogeToken, "0xf5fa014271b7971cb0ae960d445db3cb3802dfd9");

  const dogeEthPrice = await dogeToken.callStatic.dogeEthPrice();
  console.log("Doge-Eth price: " + dogeEthPrice);

  // Operators
  const operatorsLength = await dogeToken.getOperatorsLength();
  console.log("operators length: " + operatorsLength);
  for (let i = 0; i < operatorsLength; i++) {
    const operatorKey = await dogeToken.operatorKeys(i);
    if (operatorKey[1] == false) {
      // not deleted
      const operatorPublicKeyHash = operatorKey[0];
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      console.log(
        `operator [${operatorPublicKeyHash}]:
  eth address: ${operator[0]},
  dogeAvailableBalance: ${operator[1]},
  dogePendingBalance: ${operator[2]},
  nextUnspentUtxoIndex: ${operator[3]},
  ethBalance: ${hre.web3.utils.fromWei(operator[4].toString())}`
      );
      const utxosLength = await dogeToken.getUtxosLength(operatorPublicKeyHash);
      console.log("utxosLength: " + utxosLength);
      for (let j = 0; j < utxosLength; j++) {
        const utxo = await dogeToken.getUtxo(operatorPublicKeyHash, j);
        console.log(
          `utxo [${j}]: ${utxo[1].toHexString()}, ${
            utxo[2]
          }, ${utxo[0]}`
        );
      }
    }
  }

  // Current block number
  const ethBlockNumber = await hre.web3.eth.getBlockNumber();
  console.log("Eth Current block: " + ethBlockNumber);

  // Unlock events
  const unlockRequestFilter = dogeToken.filters.UnlockRequest();
  const unlockRequestEvents = await dogeToken.queryFilter(
    unlockRequestFilter,
    0,
    "latest"
  );
  await printUnlockEvent(unlockRequestEvents, dogeToken);

  // Lock events
  const dogeTokenLockFilter = dogeToken.filters.NewToken();
  const dogeTokenLockEvents = await dogeToken.queryFilter(
    dogeTokenLockFilter,
    0,
    "latest"
  );
  await printLockEvent(dogeTokenLockEvents, dogeToken);

  // Error events
  const dogeTokenErrorFilter = dogeToken.filters.ErrorDogeToken();
  const dogeTokenErrorEvents = await dogeToken.queryFilter(
    dogeTokenErrorFilter,
    0,
    "latest"
  );
  console.log("dogeTokenErrorEvents");
  console.log(dogeTokenErrorEvents);
}

async function printUnlockEvent(events: Event[], dogeToken: Contract) {
  if (events.length === 0) {
    console.log("No unlock events.");
    return;
  }

  console.log("Unlock events");

  for (const event of events) {
    if (event.args === undefined) {
      throw new Error("Arguments missing in unlock event.");
    }
    const [
      from,
      dogeAddress,
      value,
      operatorFee,
      timestamp,
      selectedUtxos,
      dogeTxFee,
      operatorPublicKeyHash,
    ] = await dogeToken.getUnlockPendingInvestorProof(event.args.id, {
      blockTag: event.blockNumber,
    });
    let args = "";
    for (const [key, value] of event.args.entries()) {
      args += `${key}: ${value}  `;
    }
    console.log(`tx hash: ${event.transactionHash} log index: ${event.logIndex}
  block number: ${event.blockNumber}
  args: ${args}
  from: ${from}
  dogecoin address: ${dogeAddress}
  value: ${value}
  operator fee: ${operatorFee}
  timestamp: ${timestamp}
  selectedUtxos: ${selectedUtxos}
  doge tx fee: ${dogeTxFee}
  operator public key hash: ${operatorPublicKeyHash}`);
  }
}

async function printLockEvent(events: Event[], dogeToken: Contract) {
  if (events.length === 0) {
    console.log("No lock events.");
    return;
  }

  console.log("Lock events");

  for (const event of events) {
    if (event.args === undefined) {
      throw new Error("Arguments missing in lock event.");
    }
    let args = "";
    for (const [key, value] of event.args.entries()) {
      args += `${key}: ${value}  `;
    }
    console.log(`tx hash: ${event.transactionHash} log index: ${event.logIndex}
  block number: ${event.blockNumber}
  args: ${args}`);
  }
}

async function showBalance(dogeToken: Contract, address: string) {
  const balance = await dogeToken.callStatic.balanceOf(address);
  console.log(`DogeToken Balance of ${address}: ${balance}`);
}

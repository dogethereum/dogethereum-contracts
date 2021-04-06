import type { Contract } from "ethers";
import type { HardhatRuntimeEnvironment } from "hardhat/types";
import type { DogethereumSystem } from "../deploy";

import { getWalletFor, Role } from "./signers";

const utils = require("../test/utils");

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
          `utxo [${j}]: ${utils.formatHexUint32(utxo[1].toHexString())}, ${
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
  console.log("unlockRequestEvents");
  console.log(unlockRequestEvents);
  // TODO: remove once the event output is tested and determined to be satisfactory
  // const myResults = unlockRequestEvent.get(async function(error, unlockRequestEvents){
  //    if (error) console.log("error: " + error);
  //    console.log("unlockRequestEvents length: " + unlockRequestEvents.length);
  //    for (let i = 0; i < unlockRequestEvents.length; i++) {
  //       console.log("unlockRequestEvent [" + unlockRequestEvents[i].args.id + "]: ");
  //       console.log("  tx block number: " + unlockRequestEvents[i].blockNumber);
  //       const unlock = await dogeToken.getUnlockPendingInvestorProof(unlockRequestEvents[i].args.id);
  //       console.log("  from: " + unlock[0]);
  //       console.log("  dogeAddress: " + unlock[1]);
  //       console.log("  value: " + unlock[2].toNumber());
  //       console.log("  operator fee: " + unlock[3].toNumber());
  //       console.log("  timestamp: " + unlock[4].toNumber());
  //       console.log("  selectedUtxos: ");
  //       for (let j = 0; j <  unlock[5].length; j++) {
  //         console.log("    " + unlock[5][j]);
  //       }
  //       console.log("  doge tx fee: " + unlock[6].toNumber());
  //       console.log("  operatorPublicKeyHash: " + unlock[7]);
  //    }
  // });

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

async function showBalance(dogeToken: Contract, address: string) {
  const balance = await dogeToken.callStatic.balanceOf(address);
  console.log(`DogeToken Balance of ${address}: ${balance}`);
}
import type { BigNumber } from "ethers";
import hre from "hardhat";

import { loadDeployment } from "../deploy";
import { accelerateTimeOnNewProposal } from "../tasks/common";

import { getWalletFor, Role } from "./signers";

export async function main(): Promise<void> {
  const {
    superblocks: { contract: superblocks },
    superblockClaims: { contract: superblockClaims },
    dogeToken: { contract: dogeToken },
  } = await loadDeployment(hre);

  // TODO: this script could check health of the agent and terminate
  // with an error if it's dead before the lock is processed.
  // To do so, it's probably convenient to turn this into a Hardhat task.

  // TODO: parametrize account?
  const userWallet = getWalletFor(Role.User);
  let balance = await dogeToken.callStatic.balanceOf(userWallet.address);
  const superblockTimeout: number = (await superblockClaims.superblockTimeout()).toNumber();
  let blockNumber = 0;
  console.log(`Token balance of ${userWallet.address}: ${balance}`);
  for (;;) {
    if (balance > 0) {
      break;
    }
    blockNumber = await accelerateTimeOnNewProposal(
      hre,
      superblocks,
      superblockTimeout,
      blockNumber
    );
    await delay(500);
    balance = await dogeToken.callStatic.balanceOf(userWallet.address);
  }
  console.log(`Token balance of ${userWallet.address}: ${balance}`);
}

function delay(milliseconds: number) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

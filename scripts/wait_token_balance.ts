import hre from "hardhat";
import { loadDeployment } from "../deploy";
import { getWalletFor, Role } from "./signers";

export async function main() {
  const {
    dogeToken: { contract: dogeToken },
  } = await loadDeployment(hre);
  // TODO: parametrize account?
  const userWallet = getWalletFor(Role.User);
  let balance = await dogeToken.callStatic.balanceOf(userWallet.address);
  console.log(`Token balance of ${userWallet.address}: ${balance}`);
  for (;;) {
    if (balance > 0) {
      return;
    }
    await delay(2000);
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

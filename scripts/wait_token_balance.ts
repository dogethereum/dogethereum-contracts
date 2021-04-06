import hre from "hardhat";
import { loadDeployment } from "../deploy";

export async function main() {
  const {
    dogeToken: { contract: dogeToken },
  } = await loadDeployment(hre);
  while (true) {
    // TODO: parametrize account?
    const userAddress = "0xd2394f3fad76167e7583a876c292c86ed10305da";
    const balance = await dogeToken.callStatic.balanceOf(userAddress);
    console.log(`Token balance of ${userAddress}: ${balance}`);
    if (balance > 0) {
      return;
    }
    await delay(2000);
  }
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

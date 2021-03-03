import hre from "hardhat";
import { loadDeployment } from "../deploy";

export async function main() {
  const {
    dogeToken: { contract: dogeToken },
  } = await loadDeployment(hre);
  while (true) {
    // TODO: parametrize account?
    const balance = await dogeToken.callStatic.balanceOf(
      "0xd2394f3fad76167e7583a876c292c86ed10305da"
    );
    console.log(
      `Token balance of 0xd2394f3fad76167e7583a876c292c86ed10305da: ${balance}`
    );
    if (balance > 0) {
      return;
    }
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

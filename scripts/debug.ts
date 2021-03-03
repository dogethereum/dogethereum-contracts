import type { HardhatRuntimeEnvironment } from "hardhat/types";
import hre from "hardhat";
import { loadDeployment } from "../deploy";
import { printStatus } from "./inspectStatus";

async function main() {
  const deployment = await loadDeployment(hre);
  await printStatus(hre, deployment);
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

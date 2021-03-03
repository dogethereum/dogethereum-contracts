import hre from "hardhat";
import fs from "fs-extra";
import path from "path";

import { deployDogethereum, DEPLOYMENT_JSON_NAME, getDefaultDeploymentPath, storeDeployment } from "../deploy";

async function main() {
  const deploymentDir = getDefaultDeploymentPath(hre);
  const deploymentExists = await fs.pathExists(path.join(deploymentDir, DEPLOYMENT_JSON_NAME));

  if (deploymentExists && hre.network.name !== "hardhat") {
    // We support only one deployment for each network for now.
    throw new Error(`A deployment for ${hre.network.name} already exists.`);
  }

  const deployment = await deployDogethereum(hre);
  return storeDeployment(hre, deployment, deploymentDir);
}

main().then(() => {
  process.exit(0);
}).catch((error) => {
  console.error(error);
  process.exit(1);
});

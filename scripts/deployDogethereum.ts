import hre from "hardhat";
import fs from "fs-extra";
import path from "path";

import {
  deployDogethereum,
  DEPLOYMENT_JSON_NAME,
  getDefaultDeploymentPath,
  storeDeployment,
  SuperblockOptions,
  SUPERBLOCK_OPTIONS_LOCAL,
  SUPERBLOCK_OPTIONS_INTEGRATION_FAST_SYNC,
  SUPERBLOCK_OPTIONS_INTEGRATION_SLOW_SYNC,
  SUPERBLOCK_OPTIONS_PRODUCTION,
} from "../deploy";

async function main() {
  const deploymentDir = getDefaultDeploymentPath(hre);
  const deploymentExists = await fs.pathExists(
    path.join(deploymentDir, DEPLOYMENT_JSON_NAME)
  );

  if (deploymentExists && hre.network.name !== "hardhat") {
    // We support only one deployment for each network for now.
    throw new Error(`A deployment for ${hre.network.name} already exists.`);
  }

  const deployment = await deployDogethereum(hre);
  return storeDeployment(hre, deployment, deploymentDir);
}

function getSuperblockOptions(ethereumNetworkName: string): SuperblockOptions {
  if (ethereumNetworkName === "hardhat" || ethereumNetworkName === "development") {
    return SUPERBLOCK_OPTIONS_LOCAL;
  }
  if (ethereumNetworkName === "rinkeby" || ethereumNetworkName === "ropsten" || ethereumNetworkName === "integrationDogeMain") {
    return SUPERBLOCK_OPTIONS_INTEGRATION_FAST_SYNC;
  }

  throw new Error("Unknown network.");
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

import hre from "hardhat";
import fs from "fs-extra";
import path from "path";

import {
  deployDogethereum,
  DEPLOYMENT_JSON_NAME,
  DogecoinNetworkId,
  getDefaultDeploymentPath,
  storeDeployment,
  SuperblockOptions,
  SUPERBLOCK_OPTIONS_LOCAL,
  SUPERBLOCK_OPTIONS_INTEGRATION_FAST_SYNC,
  // SUPERBLOCK_OPTIONS_INTEGRATION_SLOW_SYNC,
  // SUPERBLOCK_OPTIONS_PRODUCTION,
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

  // TODO: parametrize these when we write this as a Hardhat task.
  const dogeNetworkId = DogecoinNetworkId.Regtest;
  const superblockOptions = getSuperblockOptions(hre.network.name);

  const deployment = await deployDogethereum(
    hre,
    dogeNetworkId,
    superblockOptions
  );
  return storeDeployment(hre, deployment, deploymentDir);
}

function getSuperblockOptions(ethereumNetworkName: string): SuperblockOptions {
  if (
    ethereumNetworkName === "hardhat" ||
    ethereumNetworkName === "development" ||
    ethereumNetworkName === "integrationDogeRegtest"
  ) {
    return SUPERBLOCK_OPTIONS_LOCAL;
  }
  if (
    ethereumNetworkName === "rinkeby" ||
    ethereumNetworkName === "ropsten" ||
    ethereumNetworkName === "integrationDogeMain" ||
    ethereumNetworkName === "integrationDogeScrypt"
  ) {
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

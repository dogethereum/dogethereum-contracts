import hre from "hardhat";
import fs from "fs-extra";
import path from "path";

import {
  deployDogethereum,
  DEPLOYMENT_JSON_NAME,
  DogecoinNetworkId,
  getDefaultDeploymentPath,
  getScryptChecker,
  deployScryptCheckerDummy,
  storeDeployment,
  ScryptCheckerDeployment,
  SuperblockchainOptions,
  SUPERBLOCK_OPTIONS_LOCAL,
  SUPERBLOCK_OPTIONS_INTEGRATION_FAST_SYNC,
  // SUPERBLOCK_OPTIONS_INTEGRATION_SLOW_SYNC,
  // SUPERBLOCK_OPTIONS_PRODUCTION,
} from "../deploy";

interface PriceOracles {
  /**
   * Doge - Usd Chainlink price oracle.
   */
  dogeUsdPriceOracle?: string,
  /**
   * Eth - Usd Chainlink price oracle.
   */
  ethUsdPriceOracle?: string,
}

const mainnetOracles: PriceOracles = {
  dogeUsdPriceOracle: "0x2465CefD3b488BE410b941b1d4b2767088e2A028",
  ethUsdPriceOracle: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
}

const localOracles: PriceOracles = {};

/**
 * This script always deploys the production token.
 */
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
  const dogecoinNetworkId = DogecoinNetworkId.Regtest;
  const superblockOptions = getSuperblockchainOptions(hre.network.name);

  const { scryptChecker } = await deployOrGetScryptChecker();

  // TODO: add testnet oracles when they are available.
  let oracles: PriceOracles;
  if (hre.network.name === "mainnet") {
    oracles = mainnetOracles;
  } else {
    oracles = localOracles;
  }

  const deployment = await deployDogethereum(hre, {
    confirmations: 1,
    dogecoinNetworkId,
    superblockOptions,
    scryptChecker,
    dogeTokenContractName: "DogeToken",
    useProxy: true,
    ...oracles,
  });
  return storeDeployment(hre, deployment, deploymentDir);
}

function deployOrGetScryptChecker(): Promise<ScryptCheckerDeployment> {
  const scryptCheckerAddress = process.env.SCRYPT_CHECKER;
  if (scryptCheckerAddress === undefined) {
    throw new Error(
      `Scrypt checker contract address is missing.
Please specify the address by setting the SCRYPT_CHECKER environment variable.`
    );
  }

  if (scryptCheckerAddress === "deploy_dummy") {
    return deployScryptCheckerDummy(hre);
  }

  return getScryptChecker(hre, scryptCheckerAddress);
}

function getSuperblockchainOptions(ethereumNetworkName: string): SuperblockchainOptions {
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

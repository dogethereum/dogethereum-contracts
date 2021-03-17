import type ethers from "ethers";
import type { HardhatRuntimeEnvironment } from "hardhat/types";
import type { FactoryOptions } from "@nomiclabs/hardhat-ethers/types";
import fs from "fs-extra";
import path from "path";

export interface DogethereumContract {
  /**
   * This is the name of the contract in this project.
   * @dev The fully qualified name should be used if the contract name is not unique.
   */
  name: string;
  contract: ethers.Contract;
}

export interface DogethereumCoreSystem {
  superblocks: DogethereumContract;
  dogeMessageLibrary: DogethereumContract;
  scryptChecker: DogethereumContract;
  battleManager: DogethereumContract;
  claimManager: DogethereumContract;
}

export interface DogethereumTokenSystem {
  setLibrary: DogethereumContract;
  dogeToken: DogethereumContract;
}

export type DogethereumSystem = DogethereumCoreSystem & DogethereumTokenSystem;

export interface DogethereumFixture {
  superblocks: ethers.Contract;
  dogeMessageLibrary: ethers.Contract;
  scryptChecker: ethers.Contract;
  battleManager: ethers.Contract;
  claimManager: ethers.Contract;
  setLibrary: ethers.Contract;
  dogeToken: ethers.Contract;
}

interface ContractInfo {
  abi: any[];
  contractName: string;
  sourceName: string;
  address: string;
}

interface DeploymentInfo {
  chainId: number;
  contracts: {
    superblocks: ContractInfo;
    dogeMessageLibrary: ContractInfo;
    dogeToken: ContractInfo;
    scryptChecker: ContractInfo;
    claimManager: ContractInfo;
    battleManager: ContractInfo;
    setLibrary: ContractInfo;
  };
}

export const DEPLOYMENT_JSON_NAME = "deployment.json";

const scryptCheckerAddress = "0xfeedbeeffeedbeeffeedbeeffeedbeeffeedbeef";
// TODO: Remove these?
//const dogethereumRecipientUnitTest = '0x4d905b4b815d483cdfabcd292c6f86509d0fad82';
//const dogethereumRecipientIntegrationDogeMain = '0x0000000000000000000000000000000000000003';
//const dogethereumRecipientIntegrationDogeRegtest = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
// TODO: placeholder for ropsten oracle?
const trustedDogeEthPriceOracleRopsten =
  "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const trustedDogeEthPriceOracleRinkeby =
  "0xf001a51533bcd531d7a2f40a4579afcc19038c14";
const collateralRatio = 2;

/* ---- CONSTANTS FOR GENESIS SUPERBLOCK ---- */

// TODO: set these to their actual values
const genesisSuperblockMerkleRoot =
  "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5";
const genesisSuperblockChainWork = 0;
const genesisSuperblockLastBlockTimestamp = 1296688602;
const genesisSuperblockLastBlockHash =
  "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5";
const genesisSuperblockParentId = "0x0";

// TODO: define as enum?
const DOGE_MAINNET = 0;
const DOGE_TESTNET = 1;
const DOGE_REGTEST = 2;

// TODO: define an interface for these
const SUPERBLOCK_OPTIONS_PRODUCTION = {
  DURATION: 3600, // 60 minutes
  DELAY: 3 * 3600, // 3 hours
  TIMEOUT: 300, // 5 minutes
  CONFIRMATIONS: 3, // Superblocks required to confirm semi approved superblock
  REWARD: 10, // Monetary reward for opponent in case a battle is lost
};

const SUPERBLOCK_OPTIONS_INTEGRATION_SLOW_SYNC = {
  DURATION: 600, // 10 minutes
  DELAY: 300, // 5 minutes
  TIMEOUT: 60, // 1 minutes
  CONFIRMATIONS: 1, // Superblocks required to confirm semi approved superblock
  REWARD: 10, // Monetary reward for opponent in case a battle is lost
};

const SUPERBLOCK_OPTIONS_INTEGRATION_FAST_SYNC = {
  DURATION: 600, // 10 minutes
  DELAY: 300, // 5 minutes
  TIMEOUT: 10, // 10 seconds
  CONFIRMATIONS: 1, // Superblocks required to confirm semi approved superblock
  REWARD: 10, // Monetary reward for opponent in case a battle is lost
};

const SUPERBLOCK_OPTIONS_LOCAL = {
  DURATION: 60, // 1 minute
  DELAY: 60, // 1 minute
  TIMEOUT: 30, // 30 seconds
  CONFIRMATIONS: 1, // Superblocks required to confirm semi approved superblock
  REWARD: 10, // Monetary reward for opponent in case a battle is lost
};

async function deployToken(
  hre: HardhatRuntimeEnvironment,
  tokenContractName: "DogeToken" | "DogeTokenForTests",
  deploySigner: ethers.Signer,
  trustedDogeEthPriceOracle: string,
  { superblocks }: DogethereumCoreSystem
): Promise<DogethereumTokenSystem> {
  const setContractName = "Set";
  const setLibrary = {
    contract: await deployContract(setContractName, [], hre, {
      signer: deploySigner,
    }),
    name: setContractName,
  };
  const dogeToken = {
    contract: await deployContract(
      tokenContractName,
      [
        superblocks.contract.address,
        trustedDogeEthPriceOracle,
        collateralRatio,
      ],
      hre,
      {
        signer: deploySigner,
        libraries: {
          Set: setLibrary.contract.address,
        },
      }
    ),
    name: tokenContractName,
  };
  return { dogeToken, setLibrary };
}

async function deployMainSystem(
  hre: HardhatRuntimeEnvironment,
  network: string,
  deploySigner: ethers.Signer,
  networkId: number,
  superblockOptions: any
): Promise<DogethereumCoreSystem> {
  const dogeMessageLibraryName = "DogeMessageLibrary";
  const dogeMessageLibrary = {
    contract: await deployContract(dogeMessageLibraryName, [], hre, {
      signer: deploySigner,
    }),
    name: dogeMessageLibraryName,
  };

  const scryptCheckerContractName = "ScryptCheckerDummy";
  const scryptChecker = {
    contract: await deployContract(scryptCheckerContractName, [true], hre, {
      signer: deploySigner,
    }),
    name: scryptCheckerContractName,
  };

  const superblocksContractName = "DogeSuperblocks";
  const superblocks = {
    contract: await deployContract(superblocksContractName, [], hre, {
      signer: deploySigner,
      libraries: {
        DogeMessageLibrary: dogeMessageLibrary.contract.address,
      },
    }),
    name: superblocksContractName,
  };

  const battleManagerContractName = "DogeBattleManager";
  const battleManager = {
    contract: await deployContract(
      battleManagerContractName,
      [
        networkId,
        superblocks.contract.address,
        superblockOptions.DURATION,
        superblockOptions.TIMEOUT,
      ],
      hre,
      {
        signer: deploySigner,
        libraries: {
          DogeMessageLibrary: dogeMessageLibrary.contract.address,
        },
      }
    ),
    name: battleManagerContractName,
  };

  const claimManagerContractName = "DogeClaimManager";
  const claimManager = {
    contract: await deployContract(
      claimManagerContractName,
      [
        superblocks.contract.address,
        battleManager.contract.address,
        superblockOptions.DELAY,
        superblockOptions.TIMEOUT,
        superblockOptions.CONFIRMATIONS,
        superblockOptions.REWARD,
      ],
      hre,
      {
        signer: deploySigner,
      }
    ),
    name: claimManagerContractName,
  };

  await superblocks.contract.setClaimManager(claimManager.contract.address);

  await battleManager.contract.setDogeClaimManager(
    claimManager.contract.address
  );
  await battleManager.contract.setScryptChecker(scryptChecker.contract.address);

  return {
    superblocks,
    dogeMessageLibrary,
    scryptChecker,
    battleManager,
    claimManager,
  };
}

export async function deployDogethereum(
  hre: HardhatRuntimeEnvironment
): Promise<DogethereumSystem> {
  const { ethers, network } = hre;
  const accounts = await ethers.getSigners();
  let trustedDogeEthPriceOracle: string;
  if (
    network.name === "hardhat" ||
    network.name === "development" ||
    network.name === "integrationDogeRegtest" ||
    network.name === "integrationDogeMain"
  ) {
    trustedDogeEthPriceOracle = accounts[2].address;
  } else if (network.name === "ropsten") {
    trustedDogeEthPriceOracle = trustedDogeEthPriceOracleRopsten;
  } else if (network.name === "rinkeby") {
    trustedDogeEthPriceOracle = trustedDogeEthPriceOracleRinkeby;
  } else {
    trustedDogeEthPriceOracle = accounts[0].address;
  }

  const networkId =
    network.name === "integrationDogeRegtest" ? DOGE_REGTEST : DOGE_MAINNET;
  let superblockOptions;
  if (
    network.name === "ropsten" ||
    network.name === "rinkeby" ||
    network.name === "integrationDogeMain"
  ) {
    superblockOptions = SUPERBLOCK_OPTIONS_INTEGRATION_FAST_SYNC;
  } else {
    superblockOptions = SUPERBLOCK_OPTIONS_LOCAL;
  }

  const dogethereumMain = await deployMainSystem(
    hre,
    network.name,
    accounts[0],
    networkId,
    superblockOptions
  );

  let dogeTokenContracts;
  if (network.name === "hardhat" || network.name === "development") {
    dogeTokenContracts = await deployToken(
      hre,
      "DogeTokenForTests",
      accounts[0],
      trustedDogeEthPriceOracle,
      dogethereumMain
    );
  } else {
    dogeTokenContracts = await deployToken(
      hre,
      "DogeToken",
      accounts[0],
      trustedDogeEthPriceOracle,
      dogethereumMain
    );
  }

  return {
    ...dogethereumMain,
    ...dogeTokenContracts,
  };
}

export function getDefaultDeploymentPath(hre: HardhatRuntimeEnvironment) {
  return path.join(hre.config.paths.root, "deployment", hre.network.name);
}

async function getContractDescription(
  hre: HardhatRuntimeEnvironment,
  { contract, name }: DogethereumContract
) {
  const artifact = await hre.artifacts.readArtifact(name);
  return {
    abi: artifact.abi,
    contractName: artifact.contractName,
    sourceName: artifact.sourceName,
    address: contract.address,
  };
}

export async function storeDeployment(
  hre: HardhatRuntimeEnvironment,
  {
    superblocks,
    dogeMessageLibrary,
    dogeToken,
    scryptChecker,
    claimManager,
    battleManager,
    setLibrary,
  }: DogethereumSystem,
  deploymentDir: string
): Promise<void> {
  const deploymentInfo: DeploymentInfo = {
    chainId: hre.ethers.provider.network.chainId,
    contracts: {
      superblocks: await getContractDescription(hre, superblocks),
      dogeMessageLibrary: await getContractDescription(hre, dogeMessageLibrary),
      dogeToken: await getContractDescription(hre, dogeToken),
      scryptChecker: await getContractDescription(hre, scryptChecker),
      claimManager: await getContractDescription(hre, claimManager),
      battleManager: await getContractDescription(hre, battleManager),
      setLibrary: await getContractDescription(hre, setLibrary),
    },
  };
  // TODO: store debugging symbols such as storage layout, contract types, source mappings, etc too.

  await fs.ensureDir(deploymentDir);

  const deploymentJsonPath = path.join(deploymentDir, DEPLOYMENT_JSON_NAME);
  await fs.writeJson(deploymentJsonPath, deploymentInfo);

  const abiDir = path.join(deploymentDir, "abi");
  await fs.ensureDir(abiDir);

  // Here we output ABI files to generate wrapper classes in web3j.
  // Note that we don't support repeated contract names here.
  for (const info of [
    deploymentInfo.contracts.superblocks,
    deploymentInfo.contracts.dogeToken,
    deploymentInfo.contracts.claimManager,
    deploymentInfo.contracts.battleManager,
  ]) {
    const abiJsonPath = path.join(abiDir, `${info.contractName}.json`);
    const abi = info.abi;
    await fs.writeJson(abiJsonPath, abi);
  }
}

async function reifyContract(hre: HardhatRuntimeEnvironment, { abi, address, contractName }: ContractInfo) {
  const contract = await hre.ethers.getContractAt(abi, address);
  return {
    name: contractName,
    contract,
  };
}

export async function loadDeployment(
  hre: HardhatRuntimeEnvironment,
  deploymentDir: string = getDefaultDeploymentPath(hre)
): Promise<DogethereumSystem> {
  const deploymentInfoPath = path.join(deploymentDir, DEPLOYMENT_JSON_NAME);
  const deploymentInfo: DeploymentInfo = await fs.readJson(deploymentInfoPath);

  const chainId = (await hre.ethers.provider.getNetwork()).chainId;
  if (chainId !== deploymentInfo.chainId) {
    throw new Error(
      `Expected a deployment for network with chainId ${chainId} but found chainId ${deploymentInfo.chainId} instead.`
    );
  }

  return {
    superblocks: await reifyContract(hre, deploymentInfo.contracts.superblocks),
    dogeMessageLibrary: await reifyContract(hre, deploymentInfo.contracts.dogeMessageLibrary),
    dogeToken: await reifyContract(hre, deploymentInfo.contracts.dogeToken),
    scryptChecker: await reifyContract(hre, deploymentInfo.contracts.scryptChecker),
    claimManager: await reifyContract(hre, deploymentInfo.contracts.claimManager),
    battleManager: await reifyContract(hre, deploymentInfo.contracts.battleManager),
    setLibrary: await reifyContract(hre, deploymentInfo.contracts.setLibrary),
  };
}

export async function deployContract(
  contractName: string,
  constructorArguments: any[],
  { ethers }: HardhatRuntimeEnvironment,
  options: FactoryOptions = {},
  confirmations: number = 0
): Promise<ethers.Contract> {
  // TODO: `getContractFactory` gets a default signer so we may want to remove this.
  if (options.signer === undefined) {
    throw new Error("No wallet or signer defined for deployment.");
  }

  const factory = await ethers.getContractFactory(contractName, options);
  const contract = await factory.deploy(...constructorArguments);
  await contract.deployTransaction.wait(confirmations);
  return contract;
}

export async function initSuperblockChain(
  hre: HardhatRuntimeEnvironment,
  options: any
) {
  const deploySigner = await hre.ethers.getSigner(options.from);

  const dogeMessageLibrary = await deployContract(
    "DogeMessageLibrary",
    [],
    hre,
    {
      signer: deploySigner,
    }
  );

  const superblocks = await deployContract("DogeSuperblocks", [], hre, {
    signer: deploySigner,
    libraries: {
      DogeMessageLibrary: dogeMessageLibrary.address,
    },
  });
  const battleManager = await deployContract(
    "DogeBattleManager",
    [
      options.network,
      superblocks.address,
      options.params.DURATION,
      options.params.TIMEOUT,
    ],
    hre,
    {
      signer: deploySigner,
      libraries: {
        DogeMessageLibrary: dogeMessageLibrary.address,
      },
    }
  );
  const claimManager = await deployContract(
    "DogeClaimManager",
    [
      superblocks.address,
      battleManager.address,
      options.params.DELAY,
      options.params.TIMEOUT,
      options.params.CONFIRMATIONS,
      options.params.REWARD,
    ],
    hre,
    {
      signer: deploySigner,
    }
  );

  let scryptVerifier;
  let scryptChecker;
  if (options.dummyChecker) {
    scryptChecker = await deployContract("ScryptCheckerDummy", [false], hre, {
      signer: deploySigner,
    });
  } else {
    scryptVerifier = await deployContract("ScryptVerifier", [], hre, {
      signer: deploySigner,
    });
    scryptChecker = await deployContract(
      "ClaimManager",
      [scryptVerifier.address],
      hre,
      {
        signer: deploySigner,
      }
    );
  }

  await superblocks.setClaimManager(claimManager.address);
  await battleManager.setDogeClaimManager(claimManager.address);
  await battleManager.setScryptChecker(scryptChecker.address);

  await superblocks.initialize(
    options.genesisSuperblock.merkleRoot,
    options.genesisSuperblock.accumulatedWork,
    options.genesisSuperblock.timestamp,
    options.genesisSuperblock.prevTimestamp,
    options.genesisSuperblock.lastHash,
    options.genesisSuperblock.lastBits,
    options.genesisSuperblock.parentId
  );
  return {
    superblocks,
    claimManager,
    battleManager,
    scryptChecker,
    scryptVerifier,
  };
}

let dogethereumFixture: DogethereumFixture;

/**
 * This deploys the Dogethereum system the first time it's called.
 * Meant to be used in a test suite.
 * @param hre The Hardhat runtime environment where the deploy takes place.
 */
export async function deployFixture(
  hre: HardhatRuntimeEnvironment
): Promise<DogethereumFixture> {
  if (dogethereumFixture === undefined) {
    const dogethereum = await deployDogethereum(hre);
    dogethereumFixture = {
      superblocks: dogethereum.superblocks.contract,
      claimManager: dogethereum.claimManager.contract,
      battleManager: dogethereum.battleManager.contract,
      dogeToken: dogethereum.dogeToken.contract,
      setLibrary: dogethereum.setLibrary.contract,
      dogeMessageLibrary: dogethereum.dogeMessageLibrary.contract,
      scryptChecker: dogethereum.scryptChecker.contract,
    };
  }
  return dogethereumFixture;
}

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
  superblockClaims: DogethereumContract;
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
  superblockClaims: ethers.Contract;
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
    superblockClaims: ContractInfo;
    battleManager: ContractInfo;
    setLibrary: ContractInfo;
  };
}

// TODO: move to a separate module?
export interface Superblock {
  merkleRoot: string;
  accumulatedWork: string;
  timestamp: number;
  prevTimestamp: number;
  lastHash: string;
  lastBits: number;
  parentId: string;
  superblockHash: string;
  blockHeaders: string[];
  blockHashes: string[];
}

export const DEPLOYMENT_JSON_NAME = "deployment.json";

// TODO: Remove these?
// const scryptCheckerAddress = "0xfeedbeeffeedbeeffeedbeeffeedbeeffeedbeef";
//const dogethereumRecipientUnitTest = '0x4d905b4b815d483cdfabcd292c6f86509d0fad82';
//const dogethereumRecipientIntegrationDogeMain = '0x0000000000000000000000000000000000000003';
//const dogethereumRecipientIntegrationDogeRegtest = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
// TODO: placeholder for ropsten oracle?
const trustedDogeEthPriceOracleRopsten =
  "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const trustedDogeEthPriceOracleRinkeby =
  "0xf001a51533bcd531d7a2f40a4579afcc19038c14";

/* ---- CONSTANTS FOR GENESIS SUPERBLOCK ---- */

// TODO: set these to their actual values
// const genesisSuperblockMerkleRoot =
//   "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5";
// const genesisSuperblockChainWork = 0;
// const genesisSuperblockLastBlockTimestamp = 1296688602;
// const genesisSuperblockLastBlockHash =
//   "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5";
// const genesisSuperblockParentId = "0x0";

export enum DogecoinNetworkId {
  Mainnet = 0,
  Testnet = 1,
  Regtest = 2,
}

export interface SuperblockOptions {
  /**
   * Superblock duration (in seconds)
   */
  duration: number;

  /**
   * Delay to accept a superblock submission (in seconds)
   */
  delay: number;

  /**
   * Battle timeout used in the superblock DogeBattleManager and ScryptClaims.
   * This timeout is used in the challenge response protocols for both superblocks and scrypt hash verification.
   */
  timeout: number;

  /**
   * Superblocks required to confirm semi approved superblock
   */
  confirmations: number;

  /**
   * Monetary reward for opponent in case a battle is lost
   */
  reward: number;
}

// TODO: define an interface for these
export const SUPERBLOCK_OPTIONS_PRODUCTION: SuperblockOptions = {
  duration: 60 * 60,
  delay: 3 * 60 * 60,
  timeout: 5 * 60,
  confirmations: 3,
  reward: 10,
};

export const SUPERBLOCK_OPTIONS_INTEGRATION_SLOW_SYNC: SuperblockOptions = {
  duration: 10 * 60,
  delay: 5 * 60,
  timeout: 60,
  confirmations: 1,
  reward: 10,
};

/**
 * These options are typically used in testnets like ropsten, rinkeby.
 */
export const SUPERBLOCK_OPTIONS_INTEGRATION_FAST_SYNC: SuperblockOptions = {
  duration: 10 * 60,
  delay: 5 * 60,
  timeout: 30,
  confirmations: 1,
  reward: 10,
};

/**
 * These options are used for most tests.
 */
export const SUPERBLOCK_OPTIONS_LOCAL: SuperblockOptions = {
  duration: 10,
  delay: 10,
  timeout: 7,
  confirmations: 1,
  reward: 10,
};

/**
 * These options are used for some tests.
 */
export const SUPERBLOCK_OPTIONS_CLAIM_TESTS: SuperblockOptions = {
  duration: 10 * 60,
  delay: 60,
  timeout: 15,
  confirmations: 1,
  reward: 3,
};

export function getDogecoinNetworkId(networkName: string): DogecoinNetworkId {
  if (networkName === "mainnet") return DogecoinNetworkId.Mainnet;
  if (networkName === "testnet") return DogecoinNetworkId.Testnet;
  if (networkName === "regtest") return DogecoinNetworkId.Regtest;

  throw new Error("Unrecognized dogecoin network.");
}

export async function deployToken(
  hre: HardhatRuntimeEnvironment,
  tokenContractName: "DogeToken" | "DogeTokenForTests",
  deploySigner: ethers.Signer,
  trustedDogeEthPriceOracle: string,
  superblocksAddress: string,
  collateralRatio: number
): Promise<DogethereumTokenSystem> {
  const setContractName = "Set";
  const setLibrary = {
    contract: await deployContract(setContractName, [], hre, {
      signer: deploySigner,
    }),
    name: setContractName,
  };
  const dogeToken = {
    contract: await deployContract(tokenContractName, [], hre, {
      signer: deploySigner,
      libraries: {
        Set: setLibrary.contract.address,
      },
    }),
    name: tokenContractName,
  };
  await dogeToken.contract.initialize(
    superblocksAddress,
    trustedDogeEthPriceOracle,
    collateralRatio
  );
  return { dogeToken, setLibrary };
}

function deployTokenForCoreSystem(
  hre: HardhatRuntimeEnvironment,
  tokenContractName: "DogeToken" | "DogeTokenForTests",
  deploySigner: ethers.Signer,
  trustedDogeEthPriceOracle: string,
  { superblocks }: DogethereumCoreSystem,
  collateralRatio = 2
): Promise<DogethereumTokenSystem> {
  return deployToken(
    hre,
    tokenContractName,
    deploySigner,
    trustedDogeEthPriceOracle,
    superblocks.contract.address,
    collateralRatio
  );
}

async function deployScryptCheckerDummy(
  hre: HardhatRuntimeEnvironment,
  deploySigner: ethers.Signer
): Promise<DogethereumContract> {
  const scryptCheckerContractName = "ScryptCheckerDummy";
  const scryptChecker = {
    contract: await deployContract(scryptCheckerContractName, [true], hre, {
      signer: deploySigner,
    }),
    name: scryptCheckerContractName,
  };

  return scryptChecker;
}

async function deployMainSystem(
  hre: HardhatRuntimeEnvironment,
  deploySigner: ethers.Signer,
  scryptChecker: DogethereumContract,
  dogecoinNetworkId: DogecoinNetworkId,
  superblockOptions: SuperblockOptions
): Promise<DogethereumCoreSystem> {
  const dogeMessageLibraryName = "DogeMessageLibrary";
  const dogeMessageLibrary = {
    contract: await deployContract(dogeMessageLibraryName, [], hre, {
      signer: deploySigner,
    }),
    name: dogeMessageLibraryName,
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
    contract: await deployContract(battleManagerContractName, [], hre, {
      signer: deploySigner,
      libraries: {
        DogeMessageLibrary: dogeMessageLibrary.contract.address,
      },
    }),
    name: battleManagerContractName,
  };
  await battleManager.contract.initialize(
    dogecoinNetworkId,
    superblocks.contract.address,
    scryptChecker.contract.address,
    superblockOptions.duration,
    superblockOptions.timeout
  );

  const superblockClaimsContractName = "SuperblockClaims";
  const superblockClaims = {
    contract: await deployContract(superblockClaimsContractName, [], hre, {
      signer: deploySigner,
    }),
    name: superblockClaimsContractName,
  };
  await superblockClaims.contract.initialize(
    superblocks.contract.address,
    battleManager.contract.address,
    superblockOptions.delay,
    superblockOptions.timeout,
    superblockOptions.confirmations,
    superblockOptions.reward
  );

  await superblocks.contract.setSuperblockClaims(
    superblockClaims.contract.address
  );
  await battleManager.contract.setSuperblockClaims(
    superblockClaims.contract.address
  );

  return {
    superblocks,
    dogeMessageLibrary,
    scryptChecker,
    battleManager,
    superblockClaims,
  };
}

// TODO: refactor conditional properties based on network name out of this function
export async function deployDogethereum(
  hre: HardhatRuntimeEnvironment,
  dogecoinNetworkId: DogecoinNetworkId = DogecoinNetworkId.Regtest,
  superblockOptions: SuperblockOptions = SUPERBLOCK_OPTIONS_LOCAL,
  scryptCheckerAddress?: string
): Promise<DogethereumSystem> {
  const { ethers, network } = hre;
  const accounts = await ethers.getSigners();
  const deployAccount = accounts[0];
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
    trustedDogeEthPriceOracle = deployAccount.address;
  }

  let scryptChecker: DogethereumContract;
  if (scryptCheckerAddress !== undefined) {
    const scryptCheckerName = "ScryptClaims";
    scryptChecker = {
      contract: await hre.ethers.getContractAt(
        scryptCheckerName,
        scryptCheckerAddress,
        deployAccount
      ),
      name: scryptCheckerName,
    };
  } else {
    scryptChecker = await deployScryptCheckerDummy(hre, deployAccount);
  }

  const dogethereumMain = await deployMainSystem(
    hre,
    deployAccount,
    scryptChecker,
    dogecoinNetworkId,
    superblockOptions
  );

  const dogeTokenContractName =
    network.name === "hardhat" || network.name === "development"
      ? "DogeTokenForTests"
      : "DogeToken";
  const dogeTokenContracts = await deployTokenForCoreSystem(
    hre,
    dogeTokenContractName,
    deployAccount,
    trustedDogeEthPriceOracle,
    dogethereumMain
  );

  return {
    ...dogethereumMain,
    ...dogeTokenContracts,
  };
}

export function getDefaultDeploymentPath(
  hre: HardhatRuntimeEnvironment
): string {
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
    superblockClaims,
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
      superblockClaims: await getContractDescription(hre, superblockClaims),
      battleManager: await getContractDescription(hre, battleManager),
      setLibrary: await getContractDescription(hre, setLibrary),
    },
  };
  // TODO: store debugging symbols such as storage layout, contract types, source mappings, etc too.

  await fs.ensureDir(deploymentDir);

  const deploymentJsonPath = path.join(deploymentDir, DEPLOYMENT_JSON_NAME);
  await fs.writeJson(deploymentJsonPath, deploymentInfo);
}

async function reifyContract(
  hre: HardhatRuntimeEnvironment,
  { abi, address, contractName }: ContractInfo
) {
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
    dogeMessageLibrary: await reifyContract(
      hre,
      deploymentInfo.contracts.dogeMessageLibrary
    ),
    dogeToken: await reifyContract(hre, deploymentInfo.contracts.dogeToken),
    scryptChecker: await reifyContract(
      hre,
      deploymentInfo.contracts.scryptChecker
    ),
    superblockClaims: await reifyContract(
      hre,
      deploymentInfo.contracts.superblockClaims
    ),
    battleManager: await reifyContract(
      hre,
      deploymentInfo.contracts.battleManager
    ),
    setLibrary: await reifyContract(hre, deploymentInfo.contracts.setLibrary),
  };
}

export async function deployContract(
  contractName: string,
  constructorArguments: any[],
  { ethers }: HardhatRuntimeEnvironment,
  options: FactoryOptions = {},
  confirmations = 0
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
  options: {
    params: SuperblockOptions;
    network: DogecoinNetworkId;
    genesisSuperblock: Superblock;
    dummyChecker: boolean;
    from: string;
  }
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
      "ScryptClaims",
      [scryptVerifier.address],
      hre,
      {
        signer: deploySigner,
      }
    );
  }

  const battleManager = await deployContract("DogeBattleManager", [], hre, {
    signer: deploySigner,
    libraries: {
      DogeMessageLibrary: dogeMessageLibrary.address,
    },
  });
  await battleManager.initialize(
    options.network,
    superblocks.address,
    scryptChecker.address,
    options.params.duration,
    options.params.timeout
  );

  const superblockClaims = await deployContract("SuperblockClaims", [], hre, {
    signer: deploySigner,
  });
  await superblockClaims.initialize(
    superblocks.address,
    battleManager.address,
    options.params.delay,
    options.params.timeout,
    options.params.confirmations,
    options.params.reward
  );

  await superblocks.setSuperblockClaims(superblockClaims.address);
  await battleManager.setSuperblockClaims(superblockClaims.address);

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
    superblockClaims,
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
      superblockClaims: dogethereum.superblockClaims.contract,
      battleManager: dogethereum.battleManager.contract,
      dogeToken: dogethereum.dogeToken.contract,
      setLibrary: dogethereum.setLibrary.contract,
      dogeMessageLibrary: dogethereum.dogeMessageLibrary.contract,
      scryptChecker: dogethereum.scryptChecker.contract,
    };
  }
  return dogethereumFixture;
}

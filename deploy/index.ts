import type ethers from "ethers";
import type { HardhatRuntimeEnvironment } from "hardhat/types";
import type { FactoryOptions } from "@nomiclabs/hardhat-ethers/types";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import fs from "fs-extra";
import path from "path";

export interface DogethereumContract {
  /**
   * This is the name of the contract in this project.
   * @dev The fully qualified name should be used if the contract name is not unique.
   */
  name: string;
  /**
   * Object representing a concrete deployment of the contract.
   */
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

/**
 * Superblock header.
 * Fields are mostly encoded as strings to be safe.
 */
export interface SuperblockHeader {
  /**
   * Merkle root for blocks.
   * Solidity type: bytes32
   */
  merkleRoot: string;
  /**
   * Accumulated work
   * Solidity type: uint256
   */
  accumulatedWork: string;
  /**
   * Timestamp
   * Solidity type: uint256
   */
  timestamp: number;
  /**
   * Previous superblock timestamp
   * Solidity type: uint256
   */
  prevTimestamp: number;
  /**
   * Previous superblock hash
   * Solidity type: bytes32
   */
  lastHash: string;
  /**
   * Difficulty target bits
   * Solidity type: uint32
   */
  lastBits: number;
  /**
   * Parent superblock hash
   * Solidity type: bytes32
   */
  parentId: string;
}

export interface SuperblockData {
  superblockHash: string;
  blockHeaders: string[];
  blockHashes: string[];
}

export type Superblock = SuperblockHeader & SuperblockData;

export interface TokenOptions {
  /**
   * Grace period in seconds for an operator to relay an unlock tx.
   * The time window is based on the timestamp of ethereum blocks.
   */
  unlockEthereumTimeGracePeriod: number;

  /**
   * Grace period in number of superblocks for an operator to relay an unlock tx.
   * This option determines how many new confirmed superblocks need to appear
   * after an unlock request before a missing unlock tx relay is reportable.
   */
  unlockSuperblocksHeightGracePeriod: number;

  /**
   * Ratio that indicates how many value in ether wei should the operator hold in relation
   * to Dogecoin satoshis.
   * Operators can't withdraw collateral if their ratio would fall below this level by doing so.
   */
  lockCollateralRatio: string;

  /**
   * Operators that have a collateral ratio below this value are liable to liquidation.
   * This is expressed in thousandths of ethers to doges ratio. E.g. a ratio of 1.5 is expressed as 1500.
   */
  liquidationThresholdCollateralRatio: string;
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
   * This timeout is used in the challenge response protocols for superblocks.
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

  /**
   * Superblockchain genesis
   */
  genesis: SuperblockHeader;
}

export type SuperblockchainOptions = SuperblockOptions & TokenOptions;

export interface ContractOptions {
  initArguments: InitializerArguments;
  confirmations: number;
}
type InitializerArguments = any[];

type DeployF = (
  hre: HardhatRuntimeEnvironment,
  factory: ethers.ContractFactory,
  options: ContractOptions
) => Promise<ethers.Contract>;

// TODO: add deployer account?
export interface UserDogethereumDeploymentOptions {
  /**
   * Number of block confirmations to wait for when deploying a contract.
   */
  confirmations?: number;
  /**
   * Account used for deployment and initialization of contracts.
   */
  deployAccount?: SignerWithAddress;
  /**
   * Network ID of the dogecoin blockchain.
   */
  dogecoinNetworkId?: DogecoinNetworkId;
  /**
   * Address of the doge price oracle.
   */
  dogeUsdPriceOracle?: string;
  /**
   * Address of the eth price oracle.
   */
  ethUsdPriceOracle?: string;
  /**
   * Name of the token contract used in this deployment.
   */
  dogeTokenContractName: "DogeToken" | "DogeTokenForTests";
  /**
   * Superblockchain parameters.
   */
  superblockOptions?: SuperblockchainOptions;
  /**
   * Use transparent proxies to deploy main contracts
   */
  useProxy?: boolean;
}

export interface ScryptCheckerDeployment {
  scryptChecker: DogethereumContract;
}

export type DeploymentOptions = Required<UserDogethereumDeploymentOptions> &
  ScryptCheckerDeployment;
export type UserDeploymentOptions = UserDogethereumDeploymentOptions & ScryptCheckerDeployment;

export const DEPLOYMENT_JSON_NAME = "deployment.json";

export enum DogecoinNetworkId {
  Mainnet = 0,
  Testnet = 1,
  Regtest = 2,
}

// TODO: move these to another module?
// These don't actually need to have specific values for our test suites.
// We just need them to initialize the superblockchain with a known state.
const localSuperblockGenesis: SuperblockHeader = {
  merkleRoot: "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5",
  accumulatedWork: "0",
  timestamp: 1296688602,
  prevTimestamp: 0,
  lastHash: "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5",
  lastBits: 0x207fffff,
  parentId: "0x0000000000000000000000000000000000000000000000000000000000000000",
};

const integrationSuperblockGenesis: SuperblockHeader = {
  merkleRoot: "0x629417921bc4ab79db4a4a02b4d7946a4d0dbc6a3c5bca898dd12eacaeb8b353",
  accumulatedWork: "4266257060811936889868",
  timestamp: 1535743139,
  prevTimestamp: 1535743100,
  lastHash: "0xe2a056368784e63b9b5f9c17b613718ef7388a799e8535ab59be397019eff798",
  lastBits: 436759445,
  parentId: "0x0000000000000000000000000000000000000000000000000000000000000000",
};

// TODO: define adequate parameters
// export const SUPERBLOCK_OPTIONS_PRODUCTION: SuperblockchainOptions = {
//   duration: 60 * 60,
//   delay: 3 * 60 * 60,
//   timeout: 5 * 60,
//   confirmations: 3,
//   reward: 10,
//   unlockEthereumTimeGracePeriod: 24 * 60 * 60,
//   unlockSuperblocksHeightGracePeriod: 24,
//   lockCollateralRatio: "2000",
//   liquidationThresholdCollateralRatio: "1500",
// };

export const SUPERBLOCK_OPTIONS_INTEGRATION_SLOW_SYNC: SuperblockchainOptions = {
  duration: 10 * 60,
  delay: 5 * 60,
  timeout: 60,
  confirmations: 1,
  reward: 10,
  genesis: integrationSuperblockGenesis,
  unlockEthereumTimeGracePeriod: 4 * 60 * 60,
  unlockSuperblocksHeightGracePeriod: 4,
  lockCollateralRatio: "2000",
  liquidationThresholdCollateralRatio: "1500",
};

/**
 * These options are typically used in testnets like ropsten, rinkeby.
 */
export const SUPERBLOCK_OPTIONS_INTEGRATION_FAST_SYNC: SuperblockchainOptions = {
  duration: 10 * 60,
  delay: 5 * 60,
  timeout: 30,
  confirmations: 1,
  reward: 10,
  genesis: integrationSuperblockGenesis,
  unlockEthereumTimeGracePeriod: 4 * 60 * 60,
  unlockSuperblocksHeightGracePeriod: 4,
  lockCollateralRatio: "2000",
  liquidationThresholdCollateralRatio: "1500",
};

/**
 * These options are used for most tests.
 */
export const SUPERBLOCK_OPTIONS_LOCAL: SuperblockchainOptions = {
  duration: 10,
  delay: 10,
  timeout: 7,
  confirmations: 1,
  reward: 10,
  genesis: localSuperblockGenesis,
  unlockEthereumTimeGracePeriod: 10 * 60,
  unlockSuperblocksHeightGracePeriod: 1,
  lockCollateralRatio: "2000",
  liquidationThresholdCollateralRatio: "1500",
};

/**
 * These options are used for some tests.
 */
export const SUPERBLOCK_OPTIONS_CLAIM_TESTS: SuperblockchainOptions = {
  duration: 10 * 60,
  delay: 60,
  timeout: 15,
  confirmations: 1,
  reward: 3,
  genesis: localSuperblockGenesis,
  unlockEthereumTimeGracePeriod: 4 * 60 * 60,
  unlockSuperblocksHeightGracePeriod: 4,
  lockCollateralRatio: "2000",
  liquidationThresholdCollateralRatio: "1500",
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
  dogeUsdPriceOracle: string,
  ethUsdPriceOracle: string,
  txRelayerContract: string,
  superblocksAddress: string,
  {
    lockCollateralRatio,
    liquidationThresholdCollateralRatio,
    unlockEthereumTimeGracePeriod,
    unlockSuperblocksHeightGracePeriod,
  }: TokenOptions,
  confirmations = 0,
  tokenDeployPrimitive = deployPlainWithInit
): Promise<DogethereumTokenSystem> {
  const setContractName = "Set";
  const setLibrary = {
    contract: await deployContract(
      setContractName,
      [],
      hre,
      {
        signer: deploySigner,
      },
      confirmations
    ),
    name: setContractName,
  };
  const dogeToken = {
    contract: await deployContract(
      tokenContractName,
      [
        txRelayerContract,
        superblocksAddress,
        dogeUsdPriceOracle,
        ethUsdPriceOracle,
        lockCollateralRatio,
        liquidationThresholdCollateralRatio,
        unlockEthereumTimeGracePeriod,
        unlockSuperblocksHeightGracePeriod,
      ],
      hre,
      {
        signer: deploySigner,
        libraries: {
          Set: setLibrary.contract.address,
        },
      },
      confirmations,
      tokenDeployPrimitive
    ),
    name: tokenContractName,
  };
  return { dogeToken, setLibrary };
}

function deployTokenForCoreSystem(
  hre: HardhatRuntimeEnvironment,
  {
    confirmations,
    dogeTokenContractName,
    deployAccount,
    dogeUsdPriceOracle,
    ethUsdPriceOracle,
    useProxy,
    superblockOptions,
  }: DeploymentOptions,
  { superblocks }: DogethereumCoreSystem
): Promise<DogethereumTokenSystem> {
  return deployToken(
    hre,
    dogeTokenContractName,
    deployAccount,
    dogeUsdPriceOracle,
    ethUsdPriceOracle,
    superblocks.contract.address,
    superblocks.contract.address,
    superblockOptions,
    confirmations,
    useProxy ? deployProxy : deployPlainWithInit
  );
}

/**
 * This deploys a simple contract that mocks the scrypt checker system
 * implemented by ScryptClaims.
 */
export async function deployScryptCheckerDummy(
  hre: HardhatRuntimeEnvironment,
  deploySigner?: ethers.Signer
): Promise<ScryptCheckerDeployment> {
  if (deploySigner === undefined) {
    deploySigner = (await hre.ethers.getSigners())[0];
  }

  const scryptCheckerContractName = "ScryptCheckerDummy";
  const scryptChecker = {
    contract: await deployContract(scryptCheckerContractName, [true], hre, {
      signer: deploySigner,
    }),
    name: scryptCheckerContractName,
  };

  return { scryptChecker };
}

/**
 * This instantiates an interface to interact with the scrypt checker system.
 * It is assumed that the contract stored at the address given by parameter is
 * ScryptClaims.
 */
export async function getScryptChecker(
  hre: HardhatRuntimeEnvironment,
  address: string
): Promise<ScryptCheckerDeployment> {
  const scryptCheckerName = "ScryptClaims";
  const scryptChecker = {
    contract: await hre.ethers.getContractAt(scryptCheckerName, address),
    name: scryptCheckerName,
  };
  return { scryptChecker };
}

async function deployMainSystem(
  hre: HardhatRuntimeEnvironment,
  {
    confirmations,
    scryptChecker,
    dogecoinNetworkId,
    deployAccount,
    superblockOptions,
    useProxy,
  }: DeploymentOptions
): Promise<DogethereumCoreSystem> {
  const deployPrimitive: DeployF = useProxy ? deployProxy : deployPlainWithInit;

  const dogeMessageLibraryName = "DogeMessageLibrary";
  const dogeMessageLibrary = {
    contract: await deployContract(dogeMessageLibraryName, [], hre, {
      signer: deployAccount,
    }),
    name: dogeMessageLibraryName,
  };

  const superblocksContractName = "DogeSuperblocks";
  const superblocks = {
    contract: await deployContract(
      superblocksContractName,
      [],
      hre,
      {
        signer: deployAccount,
        libraries: {
          DogeMessageLibrary: dogeMessageLibrary.contract.address,
        },
      },
      confirmations,
      deployPlain
    ),
    name: superblocksContractName,
  };

  const battleManagerContractName = "DogeBattleManager";
  const battleManager = {
    contract: await deployContract(
      battleManagerContractName,
      [
        dogecoinNetworkId,
        superblocks.contract.address,
        scryptChecker.contract.address,
        superblockOptions.duration,
        superblockOptions.timeout,
      ],
      hre,
      {
        signer: deployAccount,
        libraries: {
          DogeMessageLibrary: dogeMessageLibrary.contract.address,
        },
      },
      confirmations,
      deployPrimitive
    ),
    name: battleManagerContractName,
  };

  const superblockClaimsContractName = "SuperblockClaims";
  const superblockClaims = {
    contract: await deployContract(
      superblockClaimsContractName,
      [
        superblocks.contract.address,
        battleManager.contract.address,
        superblockOptions.delay,
        superblockOptions.timeout,
        superblockOptions.confirmations,
        superblockOptions.reward,
      ],
      hre,
      {
        signer: deployAccount,
      },
      confirmations,
      deployPrimitive
    ),
    name: superblockClaimsContractName,
  };

  await superblocks.contract.setSuperblockClaims(superblockClaims.contract.address);
  await battleManager.contract.setSuperblockClaims(superblockClaims.contract.address);

  return {
    superblocks,
    dogeMessageLibrary,
    scryptChecker,
    battleManager,
    superblockClaims,
  };
}

export async function deployOracleMock(
  hre: HardhatRuntimeEnvironment,
  price: string | number,
  deployAccount: SignerWithAddress,
  confirmations: number
): Promise<ethers.Contract> {
  const oracleMock = await deployContract(
    "AggregatorMock",
    [price],
    hre,
    {
      signer: deployAccount,
    },
    confirmations
  );
  return oracleMock;
}

export async function deployDogethereum(
  hre: HardhatRuntimeEnvironment,
  {
    confirmations = 0,
    deployAccount,
    dogecoinNetworkId = DogecoinNetworkId.Regtest,
    dogeUsdPriceOracle,
    ethUsdPriceOracle,
    dogeTokenContractName = "DogeTokenForTests",
    scryptChecker,
    superblockOptions = SUPERBLOCK_OPTIONS_LOCAL,
    useProxy = false,
  }: UserDeploymentOptions
): Promise<DogethereumSystem> {
  const accounts = await hre.ethers.getSigners();
  if (deployAccount === undefined) {
    deployAccount = accounts[0];
  }
  if (dogeUsdPriceOracle === undefined) {
    const dogeUsdPrice = 29214072;
    const oracle = await deployOracleMock(hre, dogeUsdPrice, deployAccount, confirmations);
    dogeUsdPriceOracle = oracle.address;
  }
  if (ethUsdPriceOracle === undefined) {
    const ethUsdPrice = 323316156333;
    const oracle = await deployOracleMock(hre, ethUsdPrice, deployAccount, confirmations);
    ethUsdPriceOracle = oracle.address;
  }

  const deployOptions: DeploymentOptions = {
    confirmations,
    deployAccount,
    dogecoinNetworkId,
    dogeUsdPriceOracle,
    ethUsdPriceOracle,
    dogeTokenContractName,
    scryptChecker,
    superblockOptions,
    useProxy,
  };

  const dogethereumMain = await deployMainSystem(hre, deployOptions);

  const dogeTokenContracts = await deployTokenForCoreSystem(hre, deployOptions, dogethereumMain);

  return {
    ...dogethereumMain,
    ...dogeTokenContracts,
  };
}

export function getDefaultDeploymentPath(hre: HardhatRuntimeEnvironment): string {
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
    dogeMessageLibrary: await reifyContract(hre, deploymentInfo.contracts.dogeMessageLibrary),
    dogeToken: await reifyContract(hre, deploymentInfo.contracts.dogeToken),
    scryptChecker: await reifyContract(hre, deploymentInfo.contracts.scryptChecker),
    superblockClaims: await reifyContract(hre, deploymentInfo.contracts.superblockClaims),
    battleManager: await reifyContract(hre, deploymentInfo.contracts.battleManager),
    setLibrary: await reifyContract(hre, deploymentInfo.contracts.setLibrary),
  };
}

const deployProxy: DeployF = async (hre, factory, { initArguments, confirmations }) => {
  const contract = await hre.upgrades.deployProxy(factory, initArguments, {
    kind: "transparent",
    // We use a couple of external libraries so we need to tell the upgrades plugin
    // to trust our linking.
    // See https://docs.openzeppelin.com/upgrades-plugins/1.x/faq#why-cant-i-use-external-libraries
    unsafeAllow: ["external-library-linking"],
  });
  await contract.deployTransaction.wait(confirmations);
  return contract;
};

const deployPlain: DeployF = async (hre, factory, { initArguments, confirmations }) => {
  const contract = await factory.deploy(...initArguments);
  await contract.deployTransaction.wait(confirmations);
  return contract;
};

const deployPlainWithInit: DeployF = async (hre, factory, { initArguments, confirmations }) => {
  const contract = await factory.deploy();
  await contract.deployTransaction.wait(confirmations);
  const initTx = (await contract.initialize(...initArguments)) as ethers.ContractTransaction;
  await initTx.wait(confirmations);
  return contract;
};

export async function deployContract(
  contractName: string,
  initArguments: InitializerArguments,
  hre: HardhatRuntimeEnvironment,
  options: FactoryOptions = {},
  confirmations = 0,
  deployPrimitive = deployPlain
): Promise<ethers.Contract> {
  // TODO: `getContractFactory` gets a default signer so we may want to remove this.
  if (options.signer === undefined) {
    throw new Error("No wallet or signer defined for deployment.");
  }

  const factory = await hre.ethers.getContractFactory(contractName, options);
  const contract = await deployPrimitive(hre, factory, {
    initArguments,
    confirmations,
  });
  return contract;
}

export async function initSuperblockChain(
  hre: HardhatRuntimeEnvironment,
  options: {
    params: SuperblockchainOptions;
    network: DogecoinNetworkId;
    genesisSuperblock: Superblock;
    dummyChecker: boolean;
    from: string;
  }
) {
  const deployPrimitive = deployPlainWithInit;
  const deploySigner = await hre.ethers.getSigner(options.from);

  const dogeMessageLibrary = await deployContract("DogeMessageLibrary", [], hre, {
    signer: deploySigner,
  });

  const superblocks = await deployContract(
    "DogeSuperblocks",
    [
      options.genesisSuperblock.merkleRoot,
      options.genesisSuperblock.accumulatedWork,
      options.genesisSuperblock.timestamp,
      options.genesisSuperblock.prevTimestamp,
      options.genesisSuperblock.lastHash,
      options.genesisSuperblock.lastBits,
      options.genesisSuperblock.parentId,
    ],
    hre,
    {
      signer: deploySigner,
      libraries: {
        DogeMessageLibrary: dogeMessageLibrary.address,
      },
    },
    0,
    deployPrimitive
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
      "ScryptClaims",
      [scryptVerifier.address],
      hre,
      {
        signer: deploySigner,
      },
      0,
      deployPrimitive
    );
  }

  const battleManager = await deployContract(
    "DogeBattleManager",
    [
      options.network,
      superblocks.address,
      scryptChecker.address,
      options.params.duration,
      options.params.timeout,
    ],
    hre,
    {
      signer: deploySigner,
      libraries: {
        DogeMessageLibrary: dogeMessageLibrary.address,
      },
    },
    0,
    deployPrimitive
  );

  const superblockClaims = await deployContract(
    "SuperblockClaims",
    [
      superblocks.address,
      battleManager.address,
      options.params.delay,
      options.params.timeout,
      options.params.confirmations,
      options.params.reward,
    ],
    hre,
    {
      signer: deploySigner,
    },
    0,
    deployPrimitive
  );

  await superblocks.setSuperblockClaims(superblockClaims.address);
  await battleManager.setSuperblockClaims(superblockClaims.address);

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
 * In particular, it will deploy the DogeTokenForTests and ScryptCheckerDummy contracts.
 * @param hre The Hardhat runtime environment where the deploy takes place.
 */
export async function deployFixture(hre: HardhatRuntimeEnvironment): Promise<DogethereumFixture> {
  if (dogethereumFixture === undefined) {
    const { scryptChecker } = await deployScryptCheckerDummy(hre);
    const dogethereum = await deployDogethereum(hre, {
      dogeTokenContractName: "DogeTokenForTests",
      scryptChecker,
    });
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

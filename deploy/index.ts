import type ethers from "ethers";
import type { HardhatRuntimeEnvironment } from "hardhat/types";
import type { FactoryOptions } from "@nomiclabs/hardhat-ethers/types";



interface DogethereumCoreSystem {
  superblocks: ethers.Contract;
  dogeMessageLibrary: ethers.Contract;
  scryptChecker: ethers.Contract;
  battleManager: ethers.Contract;
  claimManager: ethers.Contract;
}

interface DogethereumTokenSystem {
  setLibrary: ethers.Contract;
  dogeToken: ethers.Contract;
}

type DogethereumSystem = DogethereumCoreSystem & DogethereumTokenSystem;

const scryptCheckerAddress = "0xfeedbeeffeedbeeffeedbeeffeedbeeffeedbeef";
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

async function deployTestToken(
  hre: HardhatRuntimeEnvironment,
  deploySigner: ethers.Signer,
  trustedDogeEthPriceOracle: string,
  { superblocks }: DogethereumCoreSystem
): DogethereumTokenSystem {
  const setLibrary = await deployContract("Set", [], hre, {
    signer: deploySigner,
  });
  const dogeToken = await deployContract(
    "DogeTokenForTests",
    [superblocks.address, trustedDogeEthPriceOracle, collateralRatio],
    hre,
    {
      signer: deploySigner,
      libraries: {
        Set: setLibrary.address,
      },
    }
  );
  return { dogeToken, setLibrary };
}

async function deployToken(
  hre: HardhatRuntimeEnvironment,
  deploySigner: ethers.Signer,
  trustedDogeEthPriceOracle: string,
  { superblocks, dogeMessageLibrary }: DogethereumCoreSystem
): DogethereumTokenSystem {
  const setLibrary = await deployContract("Set", [], hre, {
    signer: deploySigner,
  });
  const dogeToken = await deployContract(
    "DogeToken",
    [superblocks.address, trustedDogeEthPriceOracle, collateralRatio],
    hre,
    {
      signer: deploySigner,
      libraries: {
        DogeMessageLibrary: dogeMessageLibrary.address,
        Set: setLibrary.address,
      },
    }
  );
  return { dogeToken, setLibrary };
}

async function deployMainSystem(
  hre: HardhatRuntimeEnvironment,
  network: string,
  deploySigner: ethers.Signer,
  networkId: number,
  superblockOptions: any
): Promise<DogethereumCoreSystem> {
  const dogeMessageLibrary = await deployContract(
    "DogeMessageLibrary",
    [],
    hre,
    {
      signer: deploySigner,
    }
  );

  const scryptChecker = await deployContract(
    "ScryptCheckerDummy",
    [true],
    hre,
    { signer: deploySigner }
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
      networkId,
      superblocks.address,
      superblockOptions.DURATION,
      superblockOptions.TIMEOUT,
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
      superblockOptions.DELAY,
      superblockOptions.TIMEOUT,
      superblockOptions.CONFIRMATIONS,
      superblockOptions.REWARD,
    ],
    hre,
    {
      signer: deploySigner,
    }
  );

  await superblocks.setClaimManager(claimManager.address);

  await battleManager.setDogeClaimManager(claimManager.address);
  await battleManager.setScryptChecker(scryptChecker.address);

  return {
    superblocks,
    dogeMessageLibrary,
    scryptChecker,
    battleManager,
    claimManager,
  };
}

async function deployDogethereum(hre: HardhatRuntimeEnvironment): Promise<DogethereumSystem> {
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
    trustedDogeEthPriceOracle = accounts[0].address
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
    dogeTokenContracts = await deployTestToken(
      hre,
      accounts[0],
      trustedDogeEthPriceOracle,
      dogethereumMain
    );
  } else {
    dogeTokenContracts = await deployToken(
      hre,
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

async function deployContract(
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

async function initSuperblockChain(
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

let dogethereumFixture: DogethereumSystem;

/**
 * This deploys the Dogethereum system the first time it's called.
 * Meant to be used in a test suite.
 * @param hre The Hardhat runtime environment where the deploy takes place.
 */
export async function deployFixture(hre: HardhatRuntimeEnvironment): Promise<DogethereumSystem> {
  if (dogethereumFixture === undefined) {
    dogethereumFixture = await deployDogethereum(hre);
  }
  return dogethereumFixture;
}

module.exports = {
  deployDogethereum,
  deployFixture,
  initSuperblockChain,
  deployContract,
};

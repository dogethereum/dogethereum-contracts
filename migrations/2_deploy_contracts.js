const DummyTransactionProcessor = artifacts.require('./DummyTransactionProcessor.sol');
const Set = artifacts.require('./token/Set.sol');
const ECRecovery = artifacts.require('ECRecovery');
const DogeToken = artifacts.require('./token/DogeToken.sol');
const DogeTokenForTests = artifacts.require('./token/DogeTokenForTests.sol');
const DogeTx = artifacts.require('./DogeParser/DogeTx.sol');
const DogeTxForTests = artifacts.require('./DogeParser/DogeTxForTests.sol');
const ScryptCheckerDummy = artifacts.require('./ScryptCheckerDummy.sol');
const DogeSuperblocks = artifacts.require('./DogeSuperblocks.sol');
const DogeClaimManager = artifacts.require('./DogeClaimManager.sol');

const SafeMath = artifacts.require('openzeppelin-solidity/contracts/math/SafeMath.sol');

const scryptCheckerAddress = '0xfeedbeeffeedbeeffeedbeeffeedbeeffeedbeef';
//const dogethereumRecipientUnitTest = '0x4d905b4b815d483cdfabcd292c6f86509d0fad82';
//const dogethereumRecipientIntegrationDogeMain = '0x0000000000000000000000000000000000000003';
//const dogethereumRecipientIntegrationDogeRegtest = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
const trustedDogeEthPriceOracleRopsten = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const trustedDogeEthPriceOracleRinkeby = '0xf001a51533bcd531d7a2f40a4579afcc19038c14';
const collateralRatio = 2;

/* ---- CONSTANTS FOR GENESIS SUPERBLOCK ---- */

// TODO: set these to their actual values
const genesisSuperblockMerkleRoot = "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5";
const genesisSuperblockChainWork = 0;
const genesisSuperblockLastBlockTimestamp = 1296688602;
const genesisSuperblockLastBlockHash = "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5";
const genesisSuperblockParentId = "0x0";


const DOGE_MAINNET = 0;
const DOGE_TESTNET = 1;
const DOGE_REGTEST = 2;

const SUPERBLOCK_TIMES_PRODUCTION = {
  DURATION: 3600,   // 60 minutes
  DELAY: 3 * 3600,  // 3 hours
  TIMEOUT: 300,     // 5 minutes
  CONFIMATIONS: 3,  // Superblocks required to confirm semi approved superblock
};

const SUPERBLOCK_TIMES_INTEGRATION_SLOW_SYNC = {
  DURATION: 180,    // 3 minutes
  DELAY: 180,       // 3 minutes
  TIMEOUT: 60,      // 1 minutes
  CONFIMATIONS: 1,  // Superblocks required to confirm semi approved superblock
};

const SUPERBLOCK_TIMES_INTEGRATION_FAST_SYNC = {
  DURATION: 300,    // 5 minutes
  DELAY: 60,       // 1 minute
  TIMEOUT: 10,      // 10 seconds
  CONFIMATIONS: 1,  // Superblocks required to confirm semi approved superblock
};

const SUPERBLOCK_TIMES_LOCAL = {
  DURATION: 60,     // 1 minute
  DELAY: 60,        // 1 minute
  TIMEOUT: 10,      // 10 seconds
  CONFIMATIONS: 1,  // Superblocks required to confirm semi approved superblock
};

async function deployDevelopment(deployer, network, accounts, networkId, trustedDogeEthPriceOracle, dogethereumRecipient, superblockTimes) {
  await deployer.deploy(Set);
  await deployer.deploy(DogeTx);
  await deployer.deploy(SafeMath);
  await deployer.deploy(ECRecovery);

  await deployer.link(Set, DogeTokenForTests);
  await deployer.link(DogeTx, [DogeTxForTests, DogeTokenForTests, DogeSuperblocks, DogeClaimManager]);
  await deployer.link(ECRecovery, DogeTokenForTests);

  await deployer.deploy(DogeSuperblocks);

  await deployer.deploy(DogeTokenForTests, DogeSuperblocks.address, trustedDogeEthPriceOracle, collateralRatio);

  await deployer.deploy(DummyTransactionProcessor, DogeSuperblocks.address);

  await deployer.deploy(DogeClaimManager, networkId, DogeSuperblocks.address, superblockTimes.DURATION, superblockTimes.DELAY, superblockTimes.TIMEOUT, superblockTimes.CONFIMATIONS);

  await deployer.deploy(ScryptCheckerDummy, true)

  await deployer.deploy(DogeTxForTests);

  // await deployer.deploy(ScryptRunner);

  const superblocks = DogeSuperblocks.at(DogeSuperblocks.address);
  await superblocks.setClaimManager(DogeClaimManager.address);

  const dogeClaimManager = DogeClaimManager.at(DogeClaimManager.address);
  await dogeClaimManager.setScryptChecker(ScryptCheckerDummy.address);
}

async function deployIntegration(deployer, network, accounts, networkId, trustedDogeEthPriceOracle, dogethereumRecipient, superblockTimes) {
  await deployer.deploy(Set, {gas: 300000});
  await deployer.deploy(DogeTx, {gas: 2000000});
  await deployer.deploy(SafeMath, {gas: 100000});
  await deployer.deploy(ECRecovery, {gas: 100000});

  await deployer.link(Set, DogeToken);
  await deployer.link(DogeTx, [DogeToken, DogeSuperblocks, DogeClaimManager]);
  await deployer.link(ECRecovery, DogeToken);

  await deployer.deploy(ScryptCheckerDummy, true, {gas: 1500000})
  await deployer.deploy(DogeSuperblocks, {gas: 2700000});

  await deployer.deploy(DogeToken, DogeSuperblocks.address, trustedDogeEthPriceOracle, collateralRatio, {gas: 5300000});

  await deployer.deploy(DogeClaimManager, networkId, DogeSuperblocks.address, superblockTimes.DURATION, superblockTimes.DELAY, superblockTimes.TIMEOUT, superblockTimes.CONFIMATIONS, {gas: 7500000});

  const superblocks = DogeSuperblocks.at(DogeSuperblocks.address);
  await superblocks.setClaimManager(DogeClaimManager.address, {gas: 60000});

  const dogeClaimManager = DogeClaimManager.at(DogeClaimManager.address);
  await dogeClaimManager.setScryptChecker(ScryptCheckerDummy.address, {gas: 60000});
}

module.exports = function(deployer, network, accounts) {
  deployer.then(async () => {

    var trustedDogeEthPriceOracle;
    if (network === 'development' || network === 'integrationDogeRegtest' || network === 'integrationDogeMain') {
      trustedDogeEthPriceOracle = accounts[2]
    } else if (network === 'ropsten') {
      trustedDogeEthPriceOracle = trustedDogeEthPriceOracleRopsten;
    } else if (network === 'rinkeby') {
      trustedDogeEthPriceOracle = trustedDogeEthPriceOracleRinkeby;
    }

    if (network === 'development') {
      await deployDevelopment(deployer, network, accounts, DOGE_MAINNET, trustedDogeEthPriceOracle, null, SUPERBLOCK_TIMES_LOCAL);
    } else if (network === 'ropsten') {
      await deployIntegration(deployer, network, accounts, DOGE_MAINNET, trustedDogeEthPriceOracle, null, SUPERBLOCK_TIMES_INTEGRATION_FAST_SYNC);
    } else if (network === 'rinkeby') {
      await deployIntegration(deployer, network, accounts, DOGE_MAINNET, trustedDogeEthPriceOracle, null, SUPERBLOCK_TIMES_INTEGRATION_FAST_SYNC);
    } else if (network === 'integrationDogeMain') {
      await deployIntegration(deployer, network, accounts, DOGE_MAINNET, trustedDogeEthPriceOracle, null, SUPERBLOCK_TIMES_INTEGRATION_FAST_SYNC);
    } else if (network === 'integrationDogeRegtest') {
      await deployIntegration(deployer, network, accounts, DOGE_REGTEST, trustedDogeEthPriceOracle, null, SUPERBLOCK_TIMES_LOCAL);
    }
  });
};

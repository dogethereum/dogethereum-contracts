const DogeRelay = artifacts.require('./DogeRelay.sol');
const DogeRelayForTests = artifacts.require('./DogeRelayForTests.sol');
const DummyTransactionProcessor = artifacts.require('./DummyTransactionProcessor.sol');
const Set = artifacts.require('./token/Set.sol');
const ECRecovery = artifacts.require('ECRecovery');
const DogeToken = artifacts.require('./token/DogeToken.sol');
const DogeTokenForTests = artifacts.require('./token/DogeTokenForTests.sol');
const DogeTx = artifacts.require('./DogeParser/DogeTx.sol');
const ScryptCheckerDummy = artifacts.require('./ScryptCheckerDummy.sol');
const DogeSuperblocks = artifacts.require('./DogeSuperblocks.sol');
const DogeClaimManager = artifacts.require('./DogeClaimManager.sol');

const SafeMath = artifacts.require('openzeppelin-solidity/contracts/math/SafeMath.sol');

const ClaimManager = artifacts.require('./scriypt-interactive/ClaimManager.sol');
const ScryptVerifier = artifacts.require('./scriypt-interactive/ScryptVerifier.sol');
const ScryptRunner = artifacts.require('./scriypt-interactive/ScryptRunner.sol');

const scryptCheckerAddress = '0xfeedbeeffeedbeeffeedbeeffeedbeeffeedbeef';
//const dogethereumRecipientUnitTest = '0x4d905b4b815d483cdfabcd292c6f86509d0fad82';
//const dogethereumRecipientIntegrationDogeMain = '0x0000000000000000000000000000000000000003';
//const dogethereumRecipientIntegrationDogeRegtest = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
const trustedDogeEthPriceOracleRopsten = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const collateralRatio = 2;

const DOGE_MAINNET = 0;
const DOGE_REGTEST = 2;

async function deployDevelopment(deployer, network, accounts, networkId, trustedDogeEthPriceOracle, dogethereumRecipient) {
  await deployer.deploy(Set);
  await deployer.deploy(DogeTx);
  await deployer.deploy(SafeMath);
  await deployer.deploy(ECRecovery);

  await deployer.link(Set, DogeTokenForTests);
  await deployer.link(DogeTx, [DogeTokenForTests, DogeRelayForTests, DogeSuperblocks, DogeClaimManager]);
  await deployer.link(ECRecovery, DogeTokenForTests);
  await deployer.link(SafeMath, ClaimManager);

  await deployer.deploy(DogeRelayForTests, networkId);
  await deployer.deploy(DogeTokenForTests, DogeRelayForTests.address, trustedDogeEthPriceOracle, collateralRatio);

  await deployer.deploy(DummyTransactionProcessor, DogeRelayForTests.address);

  await deployer.deploy(DogeSuperblocks, DogeRelayForTests.address);
  await deployer.deploy(DogeClaimManager, DogeSuperblocks.address);

  await deployer.deploy(ScryptCheckerDummy, DogeRelayForTests.address, true)

  await deployer.deploy(ScryptVerifier);
  await deployer.deploy(ClaimManager, ScryptVerifier.address);
  // await deployer.deploy(ScryptRunner);

  const dogeRelay = DogeRelayForTests.at(DogeRelayForTests.address);
  await dogeRelay.setScryptChecker(ScryptCheckerDummy.address);

  const superblocks = DogeSuperblocks.at(DogeSuperblocks.address);
  await superblocks.setClaimManager(DogeClaimManager.address);

  const dogeClaimManager = DogeClaimManager.at(DogeClaimManager.address);
  await dogeClaimManager.setScryptChecker(ScryptCheckerDummy.address);
}

async function deployIntegration(deployer, network, accounts, networkId, trustedDogeEthPriceOracle, dogethereumRecipient) {
  await deployer.deploy(Set, {gas: 300000});
  await deployer.deploy(DogeTx, {gas: 2000000});
  await deployer.deploy(SafeMath, {gas: 100000});
  await deployer.deploy(ECRecovery, {gas: 100000});

  await deployer.link(Set, DogeToken);
  await deployer.link(DogeTx, [DogeToken, DogeRelay, DogeSuperblocks, DogeClaimManager]);
  await deployer.link(ECRecovery, DogeToken);
  await deployer.link(SafeMath, ClaimManager);

  await deployer.deploy(DogeRelay, networkId, {gas: 4200000});
  await deployer.deploy(ScryptCheckerDummy, DogeRelay.address, true, {gas: 1500000})
  await deployer.deploy(DogeToken, DogeRelay.address, trustedDogeEthPriceOracle, collateralRatio, {gas: 5300000});

  await deployer.deploy(DogeSuperblocks, DogeRelay.address, {gas: 2700000});
  await deployer.deploy(DogeClaimManager, DogeSuperblocks.address, {gas: 7500000});

  await deployer.deploy(ScryptVerifier, {gas: 4200000});
  await deployer.deploy(ClaimManager, ScryptVerifier.address, {gas: 5000000});
  // await deployer.deploy(ScryptRunner, {gas: 3000000});

  const dogeRelay = DogeRelay.at(DogeRelay.address);
  await dogeRelay.setScryptChecker(ScryptCheckerDummy.address, {gas: 60000});

  const superblocks = DogeSuperblocks.at(DogeSuperblocks.address);
  await superblocks.setClaimManager(DogeClaimManager.address, {gas: 60000});

  const dogeClaimManager = DogeClaimManager.at(DogeClaimManager.address);
  await dogeClaimManager.setScryptChecker(ScryptVerifier.address, {gas: 60000});
}

module.exports = function(deployer, network, accounts) {
  deployer.then(async () => {

    var trustedDogeEthPriceOracle;
    if (network === 'development' || network === 'integrationDogeRegtest' || network === 'integrationDogeMain') {
      trustedDogeEthPriceOracle = accounts[2]
    } else {
      trustedDogeEthPriceOracle = trustedDogeEthPriceOracleRopsten;
    }

    if (network === 'development') {
      await deployDevelopment(deployer, network, accounts, DOGE_MAINNET, trustedDogeEthPriceOracle);
    } else if (network === 'ropsten') {
      await deployIntegration(deployer, network, accounts, DOGE_MAINNET, trustedDogeEthPriceOracle);
    } else if (network === 'integrationDogeMain') {
      await deployIntegration(deployer, network, accounts, DOGE_MAINNET, trustedDogeEthPriceOracle);
    } else if (network === 'integrationDogeRegtest') {
      await deployIntegration(deployer, network, accounts, DOGE_REGTEST, trustedDogeEthPriceOracle);
    }
  });
};

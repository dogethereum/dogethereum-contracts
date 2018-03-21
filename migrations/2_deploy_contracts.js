const DogeRelay = artifacts.require('DogeRelay');
const DogeRelayForTests = artifacts.require('DogeRelayForTests');
const DogeProcessor = artifacts.require('DogeProcessor');
const Set = artifacts.require('token/Set');
const DogeToken = artifacts.require('token/DogeToken');
const DogeTokenForTests = artifacts.require('token/DogeTokenForTests');
const DogeTx = artifacts.require('DogeTx');
const ScryptCheckerDummy = artifacts.require('ScryptCheckerDummy');
const Superblocks = artifacts.require('Superblocks');
const ClaimManager = artifacts.require('ClaimManager');

const scryptCheckerAddress = '0xfeedbeeffeedbeeffeedbeeffeedbeeffeedbeef';
const dogethereumRecipientUnitTest = '0x4d905b4b815d483cdfabcd292c6f86509d0fad82';
const dogethereumRecipientIntegrationDogeMain = '0x0000000000000000000000000000000000000003';
const dogethereumRecipientIntegrationDogeRegtest = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
const trustedDogeEthPriceOracleRopsten = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const DOGE_MAINNET = 0;
const DOGE_REGTEST = 2;

async function deployDevelopment(deployer, network, accounts, networkId, trustedDogeEthPriceOracle, dogethereumRecipient) {
  await deployer.deploy(Set);
  await deployer.deploy(DogeTx);

  await deployer.link(Set, DogeTokenForTests);
  await deployer.link(DogeTx, DogeTokenForTests);

  await deployer.deploy(DogeRelayForTests, networkId);
  await deployer.deploy(DogeTokenForTests, DogeRelayForTests.address, trustedDogeEthPriceOracle, dogethereumRecipient);

  await deployer.deploy(DogeProcessor, DogeRelayForTests.address);

  await deployer.deploy(ScryptCheckerDummy, DogeRelayForTests.address, true)

  await deployer.deploy(Superblocks);
  await deployer.deploy(ClaimManager);

  const dogeRelay = DogeRelayForTests.at(DogeRelayForTests.address);
  await dogeRelay.setScryptChecker(ScryptCheckerDummy.address);
}

async function deployIntegration(deployer, network, accounts, networkId, trustedDogeEthPriceOracle, dogethereumRecipient) {
  await deployer.deploy(Set, {gas: 300000});
  await deployer.deploy(DogeTx, {gas: 100000});

  await deployer.link(Set, DogeToken);
  await deployer.link(DogeTx, DogeToken);

  await deployer.deploy(DogeRelay, networkId, {gas: 4500000});
  await deployer.deploy(ScryptCheckerDummy, DogeRelay.address, true, {gas: 1000000})
  await deployer.deploy(DogeToken, DogeRelay.address, trustedDogeEthPriceOracle, dogethereumRecipient, {gas: 4500000});
  
  const dogeRelay = DogeRelay.at(DogeRelay.address);
  await dogeRelay.setScryptChecker(ScryptCheckerDummy.address, {gas: 100000});
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
      await deployDevelopment(deployer, network, accounts, DOGE_MAINNET, trustedDogeEthPriceOracle, dogethereumRecipientUnitTest);
    } else if (network === 'ropsten') {
      await deployIntegration(deployer, network, accounts, DOGE_MAINNET, trustedDogeEthPriceOracle, dogethereumRecipientIntegrationDogeMain);
    } else if (network === 'integrationDogeMain') {
      await deployIntegration(deployer, network, accounts, DOGE_MAINNET, trustedDogeEthPriceOracle, dogethereumRecipientIntegrationDogeMain);
    } else if (network === 'integrationDogeRegtest') {
      await deployIntegration(deployer, network, accounts, DOGE_REGTEST, trustedDogeEthPriceOracle, dogethereumRecipientIntegrationDogeRegtest);
    }
  });
};

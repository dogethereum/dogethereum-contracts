const DogeRelay = artifacts.require('DogeRelay');
const DogeRelayForTests = artifacts.require('DogeRelayForTests');
const DogeProcessor = artifacts.require('DogeProcessor');
const Set = artifacts.require('token/Set');
const DogeToken = artifacts.require('token/DogeToken');
const DogeTokenForTests = artifacts.require('token/DogeTokenForTests');
const DogeTx = artifacts.require('DogeTx');
const ScryptCheckerDummy = artifacts.require('ScryptCheckerDummy');

const scryptCheckerAddress = '0xfeedbeeffeedbeeffeedbeeffeedbeeffeedbeef';
const dogethereumRecipientUnitTest = '0x4d905b4b815d483cdfabcd292c6f86509d0fad82';
const dogethereumRecipientIntegrationDogeMain = '0x0000000000000000000000000000000000000003';
const dogethereumRecipientIntegrationDogeRegtest = '0x0000000000000000000000000000000000000004';

const DOGE_MAINNET = 0;
const DOGE_REGTEST = 2;

async function deployDevelopment(deployer, network, accounts, networkId, dogethereumRecipient) {
  await deployer.deploy(Set);
  await deployer.deploy(DogeTx);

  await deployer.link(Set, DogeTokenForTests);
  await deployer.link(DogeTx, DogeTokenForTests);

  await deployer.deploy(DogeRelayForTests, networkId);
  await deployer.deploy(ScryptCheckerDummy, DogeRelayForTests.address, true)
  await deployer.deploy(DogeProcessor, DogeRelayForTests.address);
  await deployer.deploy(DogeTokenForTests, DogeRelayForTests.address, dogethereumRecipient);

  const dogeRelay = DogeRelayForTests.at(DogeRelayForTests.address);
  await dogeRelay.setScryptChecker(ScryptCheckerDummy.address);
}

async function deployProduction(deployer, network, accounts, networkId, dogethereumRecipient) {
  await deployer.deploy(Set);
  await deployer.deploy(DogeTx);

  await deployer.link(Set, DogeToken);
  await deployer.link(DogeTx, DogeToken);

  await deployer.deploy(DogeRelay, networkId);
  await deployer.deploy(DogeToken, DogeRelay.address, dogethereumRecipient);

  await deployer.deploy(ScryptCheckerDummy, DogeRelay.address, true)

  const dogeRelay = DogeRelay.at(DogeRelay.address);
  await dogeRelay.setScryptChecker(ScryptCheckerDummy.address);
}

module.exports = function(deployer, network, accounts) {
  deployer.then(async () => {
    if (network === 'development' || network === 'ropsten') {
      await deployDevelopment(deployer, network, accounts, DOGE_MAINNET, dogethereumRecipientUnitTest);
    } else if (network === 'integrationDogeMain') {
      await deployProduction(deployer, network, accounts, DOGE_MAINNET, dogethereumRecipientIntegrationDogeMain);
    } else if (network === 'integrationDogeRegtest') {
      await deployProduction(deployer, network, accounts, DOGE_REGTEST, dogethereumRecipientIntegrationDogeRegtest);
    }
  });
};

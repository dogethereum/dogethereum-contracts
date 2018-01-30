var DogeRelay = artifacts.require("./DogeRelay.sol");
var DogeRelayForTests = artifacts.require("./DogeRelayForTests.sol");
var DogeProcessor = artifacts.require("./DogeProcessor.sol");
var Set = artifacts.require("./token/Set.sol");
var DogeToken = artifacts.require("./token/DogeToken.sol");
var DogeTx = artifacts.require("./DogeParser/DogeTx.sol");
var ScryptCheckerDummy = artifacts.require("./ScryptCheckerDummy.sol");

const scryptCheckerAddress = '0xfeedbeeffeedbeeffeedbeeffeedbeeffeedbeef';
const dogethereumRecipientUnitTest = '0x4d905b4b815d483cdfabcd292c6f86509d0fad82';
//const dogethereumRecipient = '0xda8271ee26545028ca332368c60358a4c550d7a1';
const dogethereumRecipientIntegrationTest = '0x0000000000000000000000000000000000000002';

module.exports = function(deployer, network, accounts) {
  const dogethereumRecipient = (network === 'development') ? dogethereumRecipientUnitTest : dogethereumRecipientIntegrationTest;
  deployer.deploy(Set, {gas: 300000});
  deployer.link(Set, DogeToken);
  deployer.deploy(DogeTx, {gas: 100000});
  deployer.link(DogeTx, DogeToken);
  if (network === 'development') {
    return deployer.deploy(DogeRelayForTests, 0, {gas: 4100000}).then(function () {
      return deployer.deploy(ScryptCheckerDummy, DogeRelayForTests.address, true, {gas: 1000000})
    }).then(function () {
      return deployer.deploy(DogeProcessor, DogeRelayForTests.address, {gas: 3600000});
    }).then(function () {
      return deployer.deploy(DogeToken, DogeRelayForTests.address, dogethereumRecipient, {gas: 3500000});
    }).then(function () {
      const dogeRelay = DogeRelayForTests.at(DogeRelayForTests.address);
      return dogeRelay.setScryptChecker(ScryptCheckerDummy.address, {gas: 1000000});
    });
  } else {
    return deployer.deploy(DogeRelay, 0, {gas: 3600000}).then(function () {
      return deployer.deploy(DogeToken, DogeRelay.address, dogethereumRecipient, {gas: 3500000});
    }).then(function () {
      return deployer.deploy(ScryptCheckerDummy, DogeRelay.address, true, {gas: 1000000})
    }).then(function () {
      const dogeRelay = DogeRelay.at(DogeRelay.address);
      //return dogeRelay.setScryptChecker(scryptCheckerAddress, {gas: 100000});
      return dogeRelay.setScryptChecker(ScryptCheckerDummy.address, {gas: 100000});
    });
  }
};

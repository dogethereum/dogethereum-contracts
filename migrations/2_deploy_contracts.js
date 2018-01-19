var DogeRelay = artifacts.require("./DogeRelay.sol");
var DogeRelayForTests = artifacts.require("./DogeRelayForTests.sol");
var DogeProcessor = artifacts.require("./DogeProcessor.sol");
var Set = artifacts.require("./token/Set.sol");
var DogeToken = artifacts.require("./token/DogeToken.sol");
var DogeTx = artifacts.require("./DogeParser/DogeTx.sol");
var ScryptCheckerDummy = artifacts.require("./ScryptCheckerDummy.sol");

const dogethereumRecipient = '0x4d905b4b815d483cdfabcd292c6f86509d0fad82';
const scryptCheckerAddress = '0xfeedbeeffeedbeeffeedbeeffeedbeeffeedbeef';

module.exports = function(deployer, network, accounts) {
  deployer.deploy(Set);
  deployer.link(Set, DogeToken);
  deployer.deploy(DogeTx);
  deployer.link(DogeTx, DogeToken);
  if (network === 'development') {
    deployer.deploy(DogeRelayForTests, 0).then(function () {
      return deployer.deploy(ScryptCheckerDummy, DogeRelayForTests.address, true)
    }).then(function () {
      return deployer.deploy(DogeProcessor, DogeRelayForTests.address);
    }).then(function () {
      return deployer.deploy(DogeToken, DogeRelayForTests.address, dogethereumRecipient);
    }).then(function () {
      const dogeRelay = DogeRelayForTests.at(DogeRelayForTests.address);
      return dogeRelay.setScryptChecker(ScryptCheckerDummy.address);
    });
  } else {
    return deployer.deploy(DogeRelay, 0, scryptCheckerAddress).then(function () {
      return deployer.deploy(DogeProcessor, DogeRelay.address);
    }).then(function () {
      return deployer.deploy(DogeToken, DogeRelay.address, dogethereumRecipient);
    });
  }
};

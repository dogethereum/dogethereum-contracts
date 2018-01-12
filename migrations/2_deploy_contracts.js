var DogeRelayForDeployment = artifacts.require("./DogeRelay.sol");
var DogeRelayForTests = artifacts.require("./DogeRelayForTests.sol");
var DogeProcessor = artifacts.require("./DogeProcessor.sol");
var Set = artifacts.require("./token/Set.sol");
var DogeToken = artifacts.require("./token/DogeToken.sol");
var DogeTx = artifacts.require("./doge-parser/DogeTx.sol");

const dogethereumRecipient = '0x4d905b4b815d483cdfabcd292c6f86509d0fad82';

module.exports = function(deployer, network, accounts) {
  const DogeRelay = (network === 'development') ? DogeRelayForTests : DogeRelayForDeployment;
  deployer.deploy(Set);
  deployer.link(Set, DogeToken);
  deployer.deploy(DogeTx);
  deployer.link(DogeTx, DogeToken)
  deployer.deploy(DogeRelay, 0).then(function () {
    return deployer.deploy(DogeProcessor, DogeRelay.address);
  }).then(function () {
    return deployer.deploy(DogeToken, DogeRelay.address, dogethereumRecipient);
  });
};

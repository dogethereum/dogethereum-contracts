var DogeRelay = artifacts.require("./DogeChain.sol");
var Constants = artifacts.require("./Constants.sol");
var DogeRelay = artifacts.require("./DogeRelay.sol");

module.exports = function(deployer) {
  deployer.deploy(DogeChain);
  deployer.deploy(Constants);
  deployer.link(DogeRelay, DogeRelay);
  deployer.link(Constants, DogeRelay);
  deployer.deploy(DogeRelay);
};

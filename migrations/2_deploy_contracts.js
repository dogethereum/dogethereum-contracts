//var Constants = artifacts.require("./Constants.sol");
//var DogeChain = artifacts.require("./DogeChain.sol");
var DogeRelay = artifacts.require("./DogeRelay.sol");

module.exports = function(deployer) {
  //deployer.deploy(Constants);
  //deployer.deploy(DogeChain);
  //deployer.link(Constants, DogeRelay);
  //deployer.link(DogeChain, DogeRelay);
  deployer.deploy(DogeRelay);
};

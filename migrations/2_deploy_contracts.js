//var Constants = artifacts.require("./Constants.sol");
//var DogeChain = artifacts.require("./DogeChain.sol");
var DogeRelay = artifacts.require("./DogeRelay.sol");
var BitcoinProcessor = artifacts.require("./BitcoinProcessor.sol");
var Set = artifacts.require("./token/Set.sol");
var DogeToken = artifacts.require("./token/DogeToken.sol");

module.exports = function(deployer) {
  deployer.deploy(Set);
  deployer.link(Set, DogeToken);
  //deployer.link(DogeChain, DogeRelay);
  deployer.deploy(DogeRelay).then(function(){
	  return deployer.deploy(BitcoinProcessor, DogeRelay.address);
  }).then(function(){
	  return deployer.deploy(DogeToken, DogeRelay.address);
  });
};

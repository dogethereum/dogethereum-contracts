//var Constants = artifacts.require("./Constants.sol");
//var DogeChain = artifacts.require("./DogeChain.sol");
var DogeRelay = artifacts.require("./DogeRelay.sol");
var BitcoinProcessor = artifacts.require("./BitcoinProcessor.sol");

module.exports = function(deployer) {
  //deployer.deploy(Constants);
  //deployer.deploy(DogeChain);
  //deployer.link(Constants, DogeRelay);
  //deployer.link(DogeChain, DogeRelay);
  deployer.deploy(DogeRelay).then(function(){
	  return deployer.deploy(BitcoinProcessor, DogeRelay.address);
  });
};

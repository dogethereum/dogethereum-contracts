var DogeRelay = artifacts.require("./DogeRelay.sol");

module.exports = async function(callback) {
  console.log("init_dogerelay begin");
  // Set DogeRelay inital parent 
  var dr = await DogeRelay.deployed();
  var block2079057Hash = "0x56ce90c0c12a737c500d67c17663d83c35242e32fafcd1edc9c5b6b9aee2d2c1";  
  var result = await dr.setInitialParent(block2079057Hash, 2079057, 1, {gas: 100000});     
  console.log("init_dogerelay end");
}
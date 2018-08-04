var Superblocks = artifacts.require("./DogeSuperblocks.sol");
module.exports = async function(callback) {
  console.log("init_contracts_integration begin");
  
  var sb = await Superblocks.deployed();
  // blocks from dogemain-2331583-to-2331588
  var blocksMerkleRoot = "0xb56e1308bc44483551a5d3ba426d83c2b7634b6c985a3128e48544e8d0fe4ec2";
  var accumulatedWork = web3.toBigNumber("3752336556886305017875");
  var timestamp = 1533320063;
  var prevTimestamp = 1533320029;
  var lastHash = "0xb0dbc74bc6e258e882a527206d67579cc231be743b23500a28015c96d66ed05a";
  var lastBits = 436473103;
  var parentId = "0x0";

  await sb.initialize(blocksMerkleRoot, accumulatedWork, timestamp, prevTimestamp, lastHash, lastBits, parentId);

   console.log("init_contracts_integration end");
}
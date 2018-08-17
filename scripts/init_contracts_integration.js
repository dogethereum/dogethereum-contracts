var Superblocks = artifacts.require("./DogeSuperblocks.sol");
module.exports = async function(callback) {
  console.log("init_contracts_integration begin");
  
  var sb = await Superblocks.deployed();

  var blocksMerkleRoot = "0x045162592c1002fa0f6cf39085881da54b86dea2634e6b5f55d8258ad2b7ee0c";
  var accumulatedWork = web3.toBigNumber("4018376769700331340387");
  var timestamp = 1534537759;
  var prevTimestamp = 1534537657;
  var lastHash = "0x2f3053d4292e163931b61b39b6063494ad1ec0b5820b03ef787dbec30126ab2d";
  var lastBits = 436464932;
  var parentId = "0x0";

  await sb.initialize(blocksMerkleRoot, accumulatedWork, timestamp, prevTimestamp, lastHash, lastBits, parentId);

   console.log("init_contracts_integration end");
}
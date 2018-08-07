var Superblocks = artifacts.require("./DogeSuperblocks.sol");
module.exports = async function(callback) {
  console.log("init_contracts_integration begin");
  
  var sb = await Superblocks.deployed();

  var blocksMerkleRoot = "0xd6ba2a22aae9bbe860f7df8be83cc05dfd584121aaa1868a1926a8acec3fecb3";
  var accumulatedWork = web3.toBigNumber("3832331074689355151779");
  var timestamp = 1533678578;
  var prevTimestamp = 1533678523;
  var lastHash = "0xc2c204e82ff21092797bf451acaaf9a2074bd650e2f0dca366cca7dd0cd94d9e";
  var lastBits = 436541183;
  var parentId = "0x0";

  await sb.initialize(blocksMerkleRoot, accumulatedWork, timestamp, prevTimestamp, lastHash, lastBits, parentId);

   console.log("init_contracts_integration end");
}
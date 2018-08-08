var Superblocks = artifacts.require("./DogeSuperblocks.sol");
module.exports = async function(callback) {
  console.log("init_contracts_integration begin");
  
  var sb = await Superblocks.deployed();

  var blocksMerkleRoot = "0xff41b209ad9c306a7cf09b37982aac3604e20a97f662efb78df2f564983bae05";
  var accumulatedWork = web3.toBigNumber("3852019992739818005721");
  var timestamp = 1533769178;
  var prevTimestamp = 1533769164;
  var lastHash = "0xf8e6fdf4a2d3705ffd95184a261e4bdf9746a1b50dbae93abb4dde2b4befd73c";
  var lastBits = 436623056;
  var parentId = "0x0";

  await sb.initialize(blocksMerkleRoot, accumulatedWork, timestamp, prevTimestamp, lastHash, lastBits, parentId);

   console.log("init_contracts_integration end");
}
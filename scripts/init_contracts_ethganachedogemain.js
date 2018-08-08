var DogeToken = artifacts.require("./DogeToken.sol");
var Superblocks = artifacts.require("./DogeSuperblocks.sol");
const utils = require('./../test/utils');

module.exports = async function(callback) {
  console.log("init_contracts_ethganachedogemain begin");
  
  // Calculate operator public key
  const operatorPublicKeyHash = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
  const operatorPrivateKeyString = "105bd30419904ef409e9583da955037097f22b6b23c57549fe38ab8ffa9deaa3";
  const operatorEthAddress = web3.eth.accounts[3];  

  var operatorSignItsEthAddressResult = utils.operatorSignItsEthAddress(operatorPrivateKeyString, operatorEthAddress)
  var operatorPublicKeyCompressedString = operatorSignItsEthAddressResult[0];
  var signature = operatorSignItsEthAddressResult[1];

  var dt = await DogeToken.deployed();
  await dt.addOperator(operatorPublicKeyCompressedString, signature, {from: operatorEthAddress});
  await dt.addOperatorDeposit(operatorPublicKeyHash, {value: 1000000000000000000, from : operatorEthAddress});

  var sb = await Superblocks.deployed();

  var blocksMerkleRoot = "0xff41b209ad9c306a7cf09b37982aac3604e20a97f662efb78df2f564983bae05";
  var accumulatedWork = web3.toBigNumber("3852019992739818005721");
  var timestamp = 1533769178;
  var prevTimestamp = 1533769164;
  var lastHash = "0xf8e6fdf4a2d3705ffd95184a261e4bdf9746a1b50dbae93abb4dde2b4befd73c";
  var lastBits = 436623056;
  var parentId = "0x0";

  await sb.initialize(blocksMerkleRoot, accumulatedWork, timestamp, prevTimestamp, lastHash, lastBits, parentId);

  console.log("init_contracts_ethganachedogemain end");
}
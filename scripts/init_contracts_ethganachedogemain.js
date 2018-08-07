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

  var blocksMerkleRoot = "0xd6ba2a22aae9bbe860f7df8be83cc05dfd584121aaa1868a1926a8acec3fecb3";
  var accumulatedWork = web3.toBigNumber("3832331074689355151779");
  var timestamp = 1533678578;
  var prevTimestamp = 1533678523;
  var lastHash = "0xc2c204e82ff21092797bf451acaaf9a2074bd650e2f0dca366cca7dd0cd94d9e";
  var lastBits = 436541183;
  var parentId = "0x0";

  await sb.initialize(blocksMerkleRoot, accumulatedWork, timestamp, prevTimestamp, lastHash, lastBits, parentId);

  console.log("init_contracts_ethganachedogemain end");
}
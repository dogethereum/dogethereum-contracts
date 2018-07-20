var DogeToken = artifacts.require("./DogeToken.sol");
var Superblocks = artifacts.require("./DogeSuperblocks.sol");
const utils = require('./../test/utils');

module.exports = async function(callback) {
  console.log("init_contracts_local begin");
  
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
  var blocksMerkleRoot = "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5";
  var accumulatedWork = web3.toBigNumber("0");
  var timestamp = 1296688602;
  var prevTimestamp = 0;
  var lastHash = "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5";
  var lastBits = 0x207fffff;
  var parentId = "0x0";
  await sb.initialize(blocksMerkleRoot, accumulatedWork, timestamp, prevTimestamp, lastHash, lastBits, parentId);

  console.log("init_contracts_local end");

}
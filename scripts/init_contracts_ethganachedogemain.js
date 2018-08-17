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

  var blocksMerkleRoot = "0x045162592c1002fa0f6cf39085881da54b86dea2634e6b5f55d8258ad2b7ee0c";
  var accumulatedWork = web3.toBigNumber("4018376769700331340387");
  var timestamp = 1534537759;
  var prevTimestamp = 1534537657;
  var lastHash = "0x2f3053d4292e163931b61b39b6063494ad1ec0b5820b03ef787dbec30126ab2d";
  var lastBits = 436464932;
  var parentId = "0x0";

  await sb.initialize(blocksMerkleRoot, accumulatedWork, timestamp, prevTimestamp, lastHash, lastBits, parentId);

  console.log("init_contracts_ethganachedogemain end");
}
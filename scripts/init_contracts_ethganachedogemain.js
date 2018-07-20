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
  // blocks from dogemain-2299155-to-2299210 
  //var blocksMerkleRoot = "0x49548a60f34bef021845d5d6a8485f276ed89d391ed6779e9e4cbdf3bd2d39e5";
  //var accumulatedWork = web3.toBigNumber("3294865331135006206033");
  //var timestamp = 1531295965;
  //var prevTimestamp = 1531295930;
  //var lastHash = "0xc577a73270eb1fccd4a702402089f653c771749763e0d7ebb877f47e81eb4395";
  //var lastBits = 436591711;
  // blocks from dogemain-2309215-to-2309216
  var blocksMerkleRoot = "0x1eb62592c39990b4d33b55eac0989ec9ad69099aced17b8adc56ed561b28b473";
  var accumulatedWork = web3.toBigNumber("3434911961284113526919");
  var timestamp = 1531922574;
  var prevTimestamp = 1531922557;
  var lastHash = "0x046722472396fe2883a725f97f0e63036d2064ceb271bccc175578b724833b3f";
  var lastBits = 436643408;
  var parentId = "0x0";
  await sb.initialize(blocksMerkleRoot, accumulatedWork, timestamp, prevTimestamp, lastHash, lastBits, parentId);

  console.log("init_contracts_ethganachedogemain end");
}
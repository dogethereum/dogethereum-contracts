var DogeRelay = artifacts.require("./DogeRelay.sol");
var DogeToken = artifacts.require("./DogeToken.sol");
const utils = require('./../test/utils');

module.exports = async function(callback) {
  console.log("init_dogerelay_regtest begin");
  
  // Set DogeRelay inital parent 
  var dr = await DogeRelay.deployed();
  var block57Hash = "0x77aed6d055e6a6249bf49cd6c3283fe7cf3f32dc5388deec2d73b8a9d6e89466";  
  var result = await dr.setInitialParent(block57Hash, 57, 1, {gas: 100000});
  
  // Calculate operator public key
  const operatorPublicKeyHash = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
  const operatorPrivateKeyString = "105bd30419904ef409e9583da955037097f22b6b23c57549fe38ab8ffa9deaa3";
  const operatorEthAddress = web3.eth.accounts[3];  

  var operatorSignItsEthAddressResult = utils.operatorSignItsEthAddress(operatorPrivateKeyString, operatorEthAddress)
  var operatorPublicKeyString = operatorSignItsEthAddressResult[0];
  var signature = operatorSignItsEthAddressResult[1];

  var dt = await DogeToken.deployed();
  await dt.addOperator(operatorPublicKeyString, signature, {from: operatorEthAddress});
  await dt.addOperatorDeposit(operatorPublicKeyHash, {value: 1000000000000000000, from : operatorEthAddress});

  console.log("init_dogerelay_regtest end");

}









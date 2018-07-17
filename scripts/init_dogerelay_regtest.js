var DogeToken = artifacts.require("./DogeToken.sol");
var Superblocks = artifacts.require("./DogeSuperblocks.sol");
// var ClaimManager = artifacts.require("./ClaimManager.sol");
const utils = require('./../test/utils');

module.exports = async function(callback) {
  console.log("init_dogerelay_regtest begin");
  
  // Set DogeRelay inital parent 
  var block57Hash = "0x77aed6d055e6a6249bf49cd6c3283fe7cf3f32dc5388deec2d73b8a9d6e89466";  
  
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
//   TODO: save these in variables
  await sb.initialize("0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5", 0, 1296688602, 0, "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5", 0x207fffff, "0x0");

  console.log("Superblock initialisation successful!");

  console.log("init_dogerelay_regtest end");

}

// var DogeRelay = artifacts.require("./DogeRelay.sol");
// var Superblocks = artifacts.require("./DogeSuperblocks.sol");
// // var ClaimManager = artifacts.require("./ClaimManager.sol");

// module.exports = function(callback) {
//   var dr;
//   DogeRelay.deployed().then(function(instance) {      
//     dr = instance;
//     var block57Hash = "0x77aed6d055e6a6249bf49cd6c3283fe7cf3f32dc5388deec2d73b8a9d6e89466";
//     return dr.setInitialParent(block57Hash, 57, 1, {gas: 100000});
//   }).then(function(result) {
//     // If this callback is called, the transaction was successfully processed.
//     console.log("Transaction successful!");
//     callback();
//   }).catch(function(e) {
//     // There was an error! Handle it.
//     console.log(e);
//     callback(e);
//   });
//   Superblocks.deployed().then(function(instance) {
//     sb = instance;
// // TODO: save these in variables
//     return sb.initialize("0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5", 0, 1296688602, "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5", "0x0");
//   }).then(function(result) {
//       console.log("Superblock initialisation successful!");
//       callback();
//   }).catch(function(e) {
//       console.log(e);
//       callback(e);
//   });
// }
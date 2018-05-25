var DogeRelay = artifacts.require("./DogeRelay.sol");
var DogeToken = artifacts.require("./DogeToken.sol");
var bitcoreLib = require('bitcore-lib');
var ECDSA = bitcoreLib.crypto.ECDSA;
var bitcoreMessage = require('bitcore-message');
var buffer = require('buffer');
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
  const operatorPrivateKey = bitcoreLib.PrivateKey(buffer.Buffer.from(operatorPrivateKeyString, 'hex'));
  const operatorPublicKeyString = "0x" + operatorPrivateKey.toPublicKey().toString();

  // Calculate operator eth address hash
  const operatorEthAddress = web3.eth.accounts[3];  
  const operatorEthAddressHash = bitcoreLib.crypto.Hash.sha256sha256(buffer.Buffer.from(utils.remove0x(operatorEthAddress), 'hex'));

  // Operator private key sign operator eth address hash
  var ecdsa = new ECDSA();
  ecdsa.hashbuf = operatorEthAddressHash;
  ecdsa.privkey = operatorPrivateKey;
  ecdsa.pubkey = operatorPrivateKey.toPublicKey();
  ecdsa.signRandomK();
  ecdsa.calci();
  var ecdsaSig = ecdsa.sig;
  var signature = "0x" + ecdsaSig.toCompact().toString('hex');

  var dt = await DogeToken.deployed();
  await dt.addOperator(operatorPublicKeyString, signature, {from: operatorEthAddress});
  await dt.addOperatorDeposit(operatorPublicKeyHash, {value: 1000000000000000000, from : operatorEthAddress});

  console.log("init_dogerelay_regtest end");

  //const message = new bitcoreMessage(operatorEthAddressHash);
  //const signature = message.sign(operatorPrivateKey);

  //console.log("operatorPrivateKey " + operatorPrivateKey.inspect());
  //console.log("operatorEthAddress " + operatorEthAddress);
  //console.log("operatorEthAddressHash instanceof Buffer " + Buffer.isBuffer(operatorEthAddressHash));
  //console.log("operatorEthAddressHash instanceof string " + operatorEthAddressHash instanceof String);
  //console.log("operatorEthAddressHash " + operatorEthAddressHash.toString('hex'));
  //console.log("pub key " + operatorPublicKeyString);
  //console.log("signature " + signature);  

}









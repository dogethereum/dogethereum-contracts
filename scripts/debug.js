var DogeRelay = artifacts.require("./DogeRelay.sol");
var DogeToken = artifacts.require("./token/DogeToken.sol");
var utils = require('../test/utils');

module.exports = async function(callback) {
  var dr  = await DogeRelay.deployed();
  console.log("DogeRelay");
  console.log("---------");
  var bestBlockHash = await dr.getBestBlockHash.call(); 
  console.log("Best block hash : " + bestBlockHash.toString(16));
  var bestBlockHeight = await dr.getBestBlockHeight.call(); 
  console.log("Best block height : " + bestBlockHeight.toString(10));
  var blockLocator = await dr.getBlockLocator.call();     
  var blockLocatorFormatted = new Array();
  blockLocator.forEach(function(element) {
      blockLocatorFormatted.push(utils.formatHexUint32(element.toString(16)));
  });    
  console.log("Locator : " + blockLocatorFormatted);
  
  console.log("DogeToken");
  console.log("---------");
  var dt = await DogeToken.deployed();
  var balance1 = await dt.balanceOf.call("0x92ecc1ba4ea10f681dcf35c02f583e59d2b99b4b"); 
  console.log("DogeToken Balance of 0x92ecc1ba4ea10f681dcf35c02f583e59d2b99b4b : " + balance1);
  var balance2 = await dt.balanceOf.call("0xd2394f3fad76167e7583a876c292c86ed10305da"); 
  console.log("DogeToken Balance of 0xd2394f3fad76167e7583a876c292c86ed10305da : " + balance2);
  var dogeEthPrice = await dt.dogeEthPrice.call(); 
  console.log("Doge-Eth price : " + dogeEthPrice);
  const nextUnspentUtxoIndex = await dt.nextUnspentUtxoIndex();
  console.log("nextUnspentUtxoIndex : " + nextUnspentUtxoIndex);  
  const utxosLength = await dt.getUtxosLength();
  console.log("utxosLength : " + utxosLength);  
  for (var i = 0; i < utxosLength; i++) {
    var utxo = await dt.utxos(i);
    console.log("utxo [" + i + "]: " + utxo);  
  }
}
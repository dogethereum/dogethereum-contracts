var DogeRelay = artifacts.require("./DogeRelay.sol");
var DogeToken = artifacts.require("./token/DogeToken.sol");
var utils = require('../test/utils');

module.exports = function(callback) {
  var dr;
  var dt;  
  DogeRelay.deployed().then(function(instance) {      
    dr = instance;
    return dr.getBestBlockHash.call(); 
  }).then(function(result) {
    console.log("Best block hash : " + result.toString(16));
    return dr.getBestBlockHeight.call(); 
  }).then(function(result) {
    console.log("Best block height : " + result.toString(10));
    return dr.getBlockLocator.call();     
  }).then(function(result) {
    var formattedResult = new Array();
    result.forEach(function(element) {
      formattedResult.push(utils.formatHexUint32(element.toString(16)));
    });    
    console.log("Locator : " + formattedResult);
    return DogeToken.deployed();
  }).then(function(instance) {
    dt = instance;
    return dt.balanceOf.call("0x92ecc1ba4ea10f681dcf35c02f583e59d2b99b4b"); 
  }).then(function(result) {
    console.log("Balance of 0x92ecc1ba4ea10f681dcf35c02f583e59d2b99b4b : " + result);
    return dt.balanceOf.call("0xd2394f3fad76167e7583a876c292c86ed10305da"); 
  }).then(function(result) {
    console.log("Balance of 0xd2394f3fad76167e7583a876c292c86ed10305da : " + result);
    return dt.dogeEthPrice.call(); 
  }).then(function(result) {
    console.log("Doge-Eth price : " + result);
    callback();
  }).catch(function(e) {
    // There was an error! Handle it.
    console.log(e);
    callback(e);
  });
}
var DogeRelayForTests = artifacts.require("./DogeRelayForTests.sol");
var DogeToken = artifacts.require("./token/DogeToken.sol");
var utils = require('../test/utils');

module.exports = function(callback) {
  var dr;
  var dt;  
  DogeRelayForTests.deployed().then(function(instance) {      
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
    return dt.balanceOf.call("0x3a6f55724e01fa66a315bd05bff7d382461867c5"); 
  }).then(function(result) {
    console.log("Balance of 0x3a6f55724e01fa66a315bd05bff7d382461867c5 : " + result);
    callback();
  }).catch(function(e) {
    // There was an error! Handle it.
    console.log(e);
    callback(e);
  });
}
var DogeRelay = artifacts.require("./DogeRelay.sol");
var DogeToken = artifacts.require("./token/DogeToken.sol");

module.exports = function(callback) {
  var dr;
  DogeRelay.deployed().then(function(instance) {      
    dr = instance;
    var block95Hash = "0x9fda0c0c4beeabeaf65b513544ce0a6ce7ecb918c58b55d89c67a22047da68c0";  
    return dr.setInitialParent(block95Hash, 95, 1, {gas: 100000});     
  }).then(function(result) {
    // If this callback is called, the transaction was successfully processed.
    console.log("Transaction successful!");
    callback();
  }).catch(function(e) {
    // There was an error! Handle it.
    console.log(e);
    callback(e);
  });
}
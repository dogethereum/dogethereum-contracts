var DogeRelay = artifacts.require("./DogeRelay.sol");
var DogeToken = artifacts.require("./token/DogeToken.sol");

module.exports = function(callback) {
  var dr;
  DogeRelay.deployed().then(function(instance) {      
    dr = instance;
    var block2075755Hash = "0x972693d9d6e5046844bf1c02b675df183a1fb737a22a1d45e8d213aedcc2d71b";  
    return dr.setInitialParent(block2075755Hash, 2075755, 1, {gas: 100000});     
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
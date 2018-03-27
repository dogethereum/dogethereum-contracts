var DogeRelay = artifacts.require("./DogeRelay.sol");

module.exports = function(callback) {
  var dr;
  DogeRelay.deployed().then(function(instance) {      
    dr = instance;
    var block2079057Hash = "0x56ce90c0c12a737c500d67c17663d83c35242e32fafcd1edc9c5b6b9aee2d2c1";  
    return dr.setInitialParent(block2079057Hash, 2079057, 1, {gas: 100000});     
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
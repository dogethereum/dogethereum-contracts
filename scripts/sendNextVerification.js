var ScryptCheckerDummy = artifacts.require("./ScryptCheckerDummy.sol");

module.exports = function(callback) {
  var scd;
  ScryptCheckerDummy.deployed().then(function(instance) {      
    scd = instance;
    return scd.sendNextVerification();     
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
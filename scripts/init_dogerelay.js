var DogeRelay = artifacts.require("./DogeRelay.sol");
var DogeToken = artifacts.require("./token/DogeToken.sol");

module.exports = function(callback) {
  var dr;
  DogeRelay.deployed().then(function(instance) {      
    dr = instance;
    //return dr.setInitialParent(block974400Hash, 974400, 1, {from: accounts[0]}); 
    //var block2020000Hash = "0x9c1cdf5d0ce3676dc0551a81215d9fed0e45e12f3f7e5b18372a81130b963a2e";  
    //return dr.setInitialParent(block2020000Hash, 2020000, 1); 
    var block2054935Hash = "0xde913ba2dba274617193a336fc3a96586b7433bf0390916a59409cf7203bf73b";  
    return dr.setInitialParent(block2054935Hash, 2054935, 1);     
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
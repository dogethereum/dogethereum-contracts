var DogeRelayForTests = artifacts.require("./DogeRelayForTests.sol");
var DogeToken = artifacts.require("./token/DogeToken.sol");

module.exports = function(callback) {
  var dr;
  DogeRelayForTests.deployed().then(function(instance) {      
    dr = instance;
    var block974400Hash = "0xa84956d6535a1be26b77379509594bdb8f186b29c3b00143dcb468015bdd16da";  
    //return dr.setInitialParent(block974400Hash, 974400, 1, {from: accounts[0]}); 
    return dr.setInitialParent(block974400Hash, 974400, 1); 
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
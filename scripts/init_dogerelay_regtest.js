var DogeRelay = artifacts.require("./DogeRelay.sol");

module.exports = function(callback) {
  var dr;
  DogeRelay.deployed().then(function(instance) {      
    dr = instance;
    var block57Hash = "0x77aed6d055e6a6249bf49cd6c3283fe7cf3f32dc5388deec2d73b8a9d6e89466";  
    return dr.setInitialParent(block57Hash, 57, 1, {gas: 100000});     
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
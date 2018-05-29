var DogeRelay = artifacts.require("./DogeRelay.sol");
var Superblocks = artifacts.require("./DogeSuperblocks.sol");
// var ClaimManager = artifacts.require("./ClaimManager.sol");

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
  Superblocks.deployed().then(function(instance) {
    sb = instance;
// TODO: save these in variables
    return sb.initialize("0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5", 0, 1296688602, "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5", "0x0");
  }).then(function(result) {
      console.log("Superblock initialisation successful!");
      callback();
  }).catch(function(e) {
      console.log(e);
      callback(e);
  });
}
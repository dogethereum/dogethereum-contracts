var DogeRelay = artifacts.require("./DogeRelayForTests.sol");

contract('DogeRelay', function(accounts) {
  it("slice middle", function() {
    return DogeRelay.deployed().then(function(instance) {
      return instance.sliceArrayPublic.call("0x000102030405060708090a", 2, 5);
    }).then(function(result) {
      assert.equal(result.toString(16), "0x020304", "Slice failed");
    });
  });
  it("slice begin", function() {
    return DogeRelay.deployed().then(function(instance) {
      return instance.sliceArrayPublic.call("0x000102030405060708090a", 0, 3);
    }).then(function(result) {
      assert.equal(result.toString(16), "0x000102", "Slice failed");
    });
  });
  it("slice end", function() {
    return DogeRelay.deployed().then(function(instance) {
      return instance.sliceArrayPublic.call("0x000102030405060708090a", 8, 11);
    }).then(function(result) {
      assert.equal(result.toString(16), "0x08090a", "Slice failed");
    });
  });
  it("slice all", function() {
    return DogeRelay.deployed().then(function(instance) {
      return instance.sliceArrayPublic.call("0x0100000050120119172a610421a6c3011dd330d9df07b63616c2cc1f1cd00200000000006657a9252aacd5c0b2940996ecff952228c3067cc38d4885efb5a4ac4247e9f337221b4d4c86041b0f2b5710", 0, 80);
    }).then(function(result) {
      assert.equal(result.toString(16), "0x0100000050120119172a610421a6c3011dd330d9df07b63616c2cc1f1cd00200000000006657a9252aacd5c0b2940996ecff952228c3067cc38d4885efb5a4ac4247e9f337221b4d4c86041b0f2b5710", "Slice failed");
    });
  });  
});

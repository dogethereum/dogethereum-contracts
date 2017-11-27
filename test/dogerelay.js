var DogeRelay = artifacts.require("./DogeRelay.sol");


contract('DogeRelay', function(accounts) {
  it("concatenate 2 hashes", function() {
    return DogeRelay.deployed().then(function(instance) {
      return instance.concatHash.call("0x8c14f0db3df150123e6f3dbbf30f8b955a8249b62ac1d1ff16284aefa3d06d87", "0xfff2525b8931402dd09222c50775608f75787bd2b87e56995a7bdd30f79702c4");
    }).then(function(concatenatedHashes) {
      assert.equal(concatenatedHashes.toString(16), "ccdafb73d8dcd0173d5d5c3c9a0770d0b3953db889dab99ef05b1907518cb815", "Concatenated hash is not the expected one");
    });
  });
  it("flip32Bytes large number", function() {
    return DogeRelay.deployed().then(function(instance) {
      return instance.flip32Bytes.call("0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20");
    }).then(function(concatenatedHashes) {
      assert.equal(concatenatedHashes.toString(16), "201f1e1d1c1b1a191817161514131211100f0e0d0c0b0a090807060504030201", "flip32Bytes not the expected one");
    });
  });
  it("flip32Bytes short number", function() {
    return DogeRelay.deployed().then(function(instance) {      
      return instance.flip32Bytes.call("0x0000000000000000000000000000000000000000000000000000000000001234");
    }).then(function(concatenatedHashes) {
      assert.equal(concatenatedHashes.toString(16), "3412000000000000000000000000000000000000000000000000000000000000", "flip32Bytes is not the expected one");
    });
  });  
  it("target from bits 1", function() {
    return DogeRelay.deployed().then(function(instance) {      
      return instance.targetFromBits.call("0x19015f53");
    }).then(function(target) {
      assert.equal(target.toNumber(), "8614444778121073626993210829679478604092861119379437256704", "target is not the expected one");
    });
  });  
  it("target from bits 2", function() {
    return DogeRelay.deployed().then(function(instance) {      
      return instance.targetFromBits.call("453281356");
    }).then(function(target) {
      assert.equal(target.toString(16), "4864c000000000000000000000000000000000000000000000000", "target is not the expected one");
    });
  });  
  it("target from bits 3", function() {
    return DogeRelay.deployed().then(function(instance) {      
      return instance.targetFromBits.call("0x1d00ffff"); // EASIEST_DIFFICULTY_TARGET
    }).then(function(target) {
      maxTargetRounded = (Math.pow(2,16) - 1) * Math.pow(2,208);  // http://bitcoin.stackexchange.com/questions/8806/what-is-difficulty-and-how-it-relates-to-target
      assert.equal(target.toNumber(), maxTargetRounded, "target is not the expected one");
    });
  });
  it("bytesToBytes32", function() {
    return DogeRelay.deployed().then(function(instance) {      
      return instance.bytesToBytes32.call("0x0102030405060708090a0b0c0d0e0f000102030405060708090a0b0c0d0e0f00"); 
    }).then(function(target) {
      assert.equal(target, "0x0102030405060708090a0b0c0d0e0f000102030405060708090a0b0c0d0e0f00", "converted bytes are not the expected ones");
    });
  });

});


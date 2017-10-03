var DogeRelay = artifacts.require("./DogeRelay.sol");

contract('DogeRelay', function(accounts) {
  it("concatenate 2 hashes", function() {
    return DogeRelay.deployed().then(function(instance) {
      return instance.concatHash.call(0x8c14f0db3df150123e6f3dbbf30f8b955a8249b62ac1d1ff16284aefa3d06d87, 0xfff2525b8931402dd09222c50775608f75787bd2b87e56995a7bdd30f79702c4);
    }).then(function(concatenatedHashes) {
      assert.equal(balance.valueOf(), 0xccdafb73d8dcd0173d5d5c3c9a0770d0b3953db889dab99ef05b1907518cb815, "Concatenated hash is not the expected one");
    });
  });
});

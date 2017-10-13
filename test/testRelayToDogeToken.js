var DogeRelay = artifacts.require("./DogeRelay.sol");
var DogeToken = artifacts.require("./token/DogeToken.sol");
var utils = require('./utils');


contract('DogeToken', function(accounts) {
 it("testRelayToDogeToken", function() {
    var dr;
    var dogeToken;    
    var txHash;
    return DogeRelay.deployed().then(function(instance) {      
      dr = instance;      
      return DogeToken.deployed();
    }).then(function(instance) {
      dogeToken = instance;
      return utils.bulkStore10From300K(dr, accounts); 
    }).then(function(headerAndHashes) {
      var txIndex = 1;
      txHash = '7301b595279ece985f0c415e420e425451fcf7f684fcce087ba14d10ffec1121';
      var txStr = '0x01000000014dff4050dcee16672e48d755c6dd25d324492b5ea306f85a3ab23b4df26e16e9000000008c493046022100cb6dc911ef0bae0ab0e6265a45f25e081fc7ea4975517c9f848f82bc2b80a909022100e30fb6bb4fb64f414c351ed3abaed7491b8f0b1b9bcd75286036df8bfabc3ea5014104b70574006425b61867d2cbb8de7c26095fbc00ba4041b061cf75b85699cb2b449c6758741f640adffa356406632610efb267cb1efa0442c207059dd7fd652eeaffffffff020049d971020000001976a91461cf5af7bb84348df3fd695672e53c7d5b3f3db988ac30601c0c060000001976a914fd4ed114ef85d350d6d40ed3f6dc23743f8f99c488ac00000000'
      var siblings = utils.makeMerkleProof(headerAndHashes.hashes, txIndex);
      for(var i = 0; i < siblings.length; i++) {
        siblings[i] = "0x" + siblings[i];
      }
      return dr.relayTx(txStr, txIndex, siblings, "0x" + headerAndHashes.header.hash, dogeToken.address);
    }).then(function(result) {
      return dogeToken.balanceOf("0xcedacadacafe");
    }).then(function(result) {
      assert.equal(result.toNumber(), 150, "DogeToken's 0xcedacadacafe balance is not the expected one");
    });    
 });
});







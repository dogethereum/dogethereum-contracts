var DogeRelay = artifacts.require("./DogeRelayForTests.sol");
var DogeProcessor = artifacts.require("./DogeProcessor.sol");
var utils = require('./utils');


contract('test_bulkStoreHeaders3', function(accounts) {
 it("testTx1In974402", function() {
    var dr;
    var dogeProcessor;
    var txHash;
    return DogeRelay.deployed().then(function(instance) {
      dr = instance;
      return DogeProcessor.deployed();
    }).then(function(instance) {
      dogeProcessor = instance;
      return utils.bulkStore10From974401(dr, accounts[0], accounts[2]);
    }).then(function(headerAndHashes) {
      var txIndex = 1; // Second tx in the block
      txHash = 'af12afe762daf75815db0097e16445dbba45ce9140f3da37b86f00b45bd627b2';
      var txStr = `0x01000000049dcc6af9db555f2ef03a99621a8206b1116126fa981aabb28dcc8521c23dd944010000006b483045022100bfa6fd0d9e61def5fc1b4dda646481d2dd97b3916b4c74a6d534992f676f988302201e92ad0b58b16cb6648ecdaf827c61ecc741c0f7ca04943893a1157ee7abd14b012102f245f8b2112be263982a368d983f4f47935a62b79b02e43b9b778a338235984affffffff0719076c63b47e01cdcd0022bd80336d4b824e54c3d0e031254109e23ba49dd4010000006a47304402206cd7e02ebcc54c837e5d3f77097b19f93f0de3c07099e22b87dd2609bcc98c3502207a47daf94ff1f56677584e8af661158b6bbf5fda861d2cb0d2ff41a44687ccb20121039da9b40e20539e80ae1f6f4aeccc7125c66af7176c964aeed37bc9c2dc01a1ffffffffff945b21842ca5230204df9752ebf514a114b7302ea233ce662def0a9cc269dee6000000006a47304402200fe15a0a00c6eb0a792874bb139c1c45888d0920ad9fba470465badb35c4f0da02200f6129828a03e7d2281bbbee231bb1609b0dc17882ae82c31585316130a59c140121028c55b3de485aac43ae3d5c48770268a429edc59224024ac3815edfbd0e3b25b8ffffffff98f8d6c53475e3d9f7ec7ad77554c26ee24b5223fc1abf2034a189e3a7ba46b6010000006b483045022100fc688eb6750a7236280af12ab3da516ac0e978c0f5ca1fbee11ddd21648fe659022044d9eb938baf96c929c5c0d96572d4d20133e900bd94a22140fa4fff170665010121023d070beb676de3cbb73bdc787f2b8c33c6c94263dbff9f94c893c8fa07fbcbccffffffff0230431029790200001976a914ea4088d4768f0f734e343b68a8a680255941465f88ac50420e1a0a5801001976a9144488a6dbd0c66c417e163158de1674285b1cba2d88ac00000000`;
      var siblings = utils.makeMerkleProof(headerAndHashes.hashes, txIndex);
      for(var i = 0; i < siblings.length; i++) {
        siblings[i] = "0x" + siblings[i];
      }
      return dr.relayTx(txStr, txIndex, siblings, "0x" + headerAndHashes.header.hash, dogeProcessor.address);
    }).then(function(result) {
      // console.log(result.receipt.logs);
      return dogeProcessor.lastTxHash();
    }).then(function(result) {
      assert.equal(utils.formatHexUint32(result.toString(16)), txHash, "DogeProcessor's last tx hash is not the expected one");
    });
 });
});

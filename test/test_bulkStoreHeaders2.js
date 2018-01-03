var fs = require('fs');
var readline = require('readline');
var DogeRelay = artifacts.require("./DogeRelayForTests.sol");
var utils = require('./utils');


contract('DogeRelay', function(accounts) {
 it("testDifficulty", function() {
    var dr;
    var headers = "0x";
    var hashes = "0x";
    return DogeRelay.deployed().then(function(instance) {
      dr = instance;
      // Doge testnet 739200
      var block739200Hash = "0x69404b833f190a1a29c32265ad73ea344ccaba82367be0d43d58a9eed2b8d357";
      return dr.setInitialParent(block739200Hash, 739200, 1, {from: accounts[0]});
    }).then(function(result) {
      return utils.parseDataFile('test/headers/elevenDogeTestnet.txt');
    }).then(function ({ headers: rawHeaders, hashes: rawHashes }) {
      headers += rawHeaders.map(utils.addSizeToHeader).join('');
      hashes += rawHeaders.map(utils.calcHeaderPoW).join('');
      return dr.bulkStoreHeaders(headers, hashes, 11, {from: accounts[0]});
    }).then(function(result) {
      //console.log(result.receipt.logs);
      return dr.getChainWork.call();
    }).then(function(result) {
      assert.equal(result.toNumber(), 11 + 1, "difficulty is not the expected one"); // # +1 since setInitialParent was called with imaginary block
      return dr.getAverageChainWork.call();
    }).then(function(result) {
      assert.equal(result.toNumber(), 10, "average chain work is not the expected one");
    });
  });


});

var DogeRelay = artifacts.require('./DogeRelayForTests.sol');
var ScryptCheckerDummy = artifacts.require('./ScryptCheckerDummy.sol');
var utils = require('./utils');


contract('DogeRelay', function(accounts) {
    let dr;
    before(async () => {
        dr = await DogeRelay.new(1);
        const scryptChecker = await ScryptCheckerDummy.new(true);
        await dr.setScryptChecker(scryptChecker.address);
    });
    it("testDifficulty", function() {
        var headers = "0x";
        var hashes = "0x";
        // Dogecoin testnet
        var block739200Hash = "0x69404b833f190a1a29c32265ad73ea344ccaba82367be0d43d58a9eed2b8d357";
        return dr.setInitialParent(block739200Hash, 739200, 1, {from: accounts[0]}).then(function(instance) {
            return utils.parseDataFile('test/headers/elevenDogeTestnet.txt');
        }).then(function ({ headers: rawHeaders, hashes: rawHashes }) {
            headers += rawHeaders.map(utils.addSizeToHeader).join('');
            hashes += rawHeaders.map(utils.calcHeaderPoW).join('');
            return dr.bulkStoreHeaders(headers, hashes, 11, accounts[2], {from: accounts[0]});
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

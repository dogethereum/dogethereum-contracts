var DogeRelay = artifacts.require('./DogeRelayForTests.sol');
var ScryptCheckerDummy = artifacts.require('./ScryptCheckerDummy.sol');
var utils = require('./utils');


contract('test_bulkStoreHeaders4', function(accounts) {
    let dr;
    before(async () => {
        dr = await DogeRelay.new(1);
        const scryptChecker = await ScryptCheckerDummy.new(dr.address, true);
        await dr.setScryptChecker(scryptChecker.address);
    });
    it("testDifficulty", function() {
        var headers = "0x";
        var hashes = "0x";
        // Dogecoin testnet
        var block145000Hash = "0x26d737ddcdaa35463e466ee870b0e75699bcffed1b3df720522b042020507c93";
        return dr.setInitialParent(block145000Hash, 145000, 1, {from: accounts[0]}).then(function(instance) {
            return utils.parseDataFile('test/headers/dogeTestnetDifficulty.txt');
        }).then(function ({ headers: rawHeaders, hashes: rawHashes }) {
            headers += rawHeaders.map(utils.addSizeToHeader).join('');
            hashes += rawHeaders.map(utils.calcHeaderPoW).join('');
            return dr.bulkStoreHeaders(headers, hashes, 11, accounts[2], {from: accounts[0]});
        }).then(function(result) {
            // console.log(result.receipt.logs);
            return dr.getChainWork.call();
        }).then(function(result) {
            assert.equal(result.toNumber(), 11 + 1, "difficulty is not the expected one"); // # +1 since setInitialParent was called with imaginary block
            return dr.getAverageChainWork.call();
        });
    });


});

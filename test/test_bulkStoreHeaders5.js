var DogeRelay = artifacts.require('./DogeRelayForTests.sol');
var ScryptCheckerDummy = artifacts.require('./ScryptCheckerDummy.sol');
var utils = require('./utils');


contract('DogeRelay', function(accounts) {
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
        var block160000Hash = "0x5a4df2c095676f3f4e064bb5973adc3bf615ece4288d9d6f6a18e4393742b0ec";
        return dr.setInitialParent(block160000Hash, 160000, 1, {from: accounts[0]}).then(function(instance) {
            return utils.parseDataFile('test/headers/dogeTestnetDifficulty160000.txt');
        }).then(function ({ headers: rawHeaders, hashes: rawHashes }) {
            headers += rawHeaders.map(utils.addSizeToHeader).join('');
            hashes += rawHeaders.map(utils.calcHeaderPoW).join('');
            return dr.bulkStoreHeaders(headers, hashes, 11, {from: accounts[0]});
        }).then(function(result) {
            // console.log(result.receipt.logs);
            return dr.getBestBlockHeight.call();
        }).then(function(result) {
            assert.equal(result.toNumber(), 160000 + 11, "getBestBlockHeight is not the expected one");
        });
    });


});

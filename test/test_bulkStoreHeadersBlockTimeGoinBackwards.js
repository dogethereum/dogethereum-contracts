var DogeRelay = artifacts.require('./DogeRelayForTests.sol');
var ScryptCheckerDummy = artifacts.require('./ScryptCheckerDummy.sol');
var utils = require('./utils');


contract('test_bulkStoreHeadersBlockTimeGoinBackwards', function(accounts) {
    let dr;
    before(async () => {
        dr = await DogeRelay.new(0);
        const scryptChecker = await ScryptCheckerDummy.new(dr.address, true);
        await dr.setScryptChecker(scryptChecker.address);
    });
    it("testDifficulty", function() {
        var headers = "0x";
        var hashes = "0x";
        // Dogecoin mainnet
        var block2054957Hash = "0x6622287c6e6638b3d087941fc062c09a53625138f33e12c8f9850503c52d2075";
        return dr.setInitialParent(block2054957Hash, 2054957, 1, {from: accounts[0]}).then(function(instance) {
            return utils.parseDataFile('test/headers/2054958to2054963Main.txt');
        }).then(function ({ headers: rawHeaders, hashes: rawHashes }) {
            headers += rawHeaders.map(utils.addSizeToHeader).join('');
            hashes += rawHeaders.map(utils.calcHeaderPoW).join('');
            return dr.bulkStoreHeaders(headers, hashes, 6, {from: accounts[0]});
        }).then(function(result) {
            //console.log(result.receipt.logs);
            return dr.getBestBlockHeight.call();
        }).then(function(result) {
            assert.equal(result.toNumber(), 2054957 + 6, "getBestBlockHeight is not the expected one");
        });
    });


});

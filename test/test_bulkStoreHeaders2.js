var DogeRelay = artifacts.require('./DogeRelayForTests.sol');
var ScryptCheckerDummy = artifacts.require('./ScryptCheckerDummy.sol');
var utils = require('./utils');


contract('test_bulkStoreHeaders2', function(accounts) {
    let dr;
    before(async () => {
        dr = await DogeRelay.new(1);
        const scryptChecker = await ScryptCheckerDummy.new(dr.address, true);
        await dr.setScryptChecker(scryptChecker.address);
    });
    it("testDifficulty", async () => {
        var headers = "0x";
        var hashes = "0x";
        // Dogecoin testnet
        var block739200Hash = "0x69404b833f190a1a29c32265ad73ea344ccaba82367be0d43d58a9eed2b8d357";
        await dr.setInitialParent(block739200Hash, 739200, 1, {from: accounts[0]});
        const { headers: rawHeaders, hashes: rawHashes } = await utils.parseDataFile('test/headers/elevenDogeTestnet.txt');
        headers += rawHeaders.map(utils.addSizeToHeader).join('');
        hashes += rawHeaders.map(utils.calcHeaderPoW).join('');
        const result = await dr.bulkStoreHeaders(headers, hashes, 11, accounts[2], {from: accounts[0]});
        //console.log(result.receipt.logs);
        const chainWork = await dr.getChainWork.call();
        assert.equal(chainWork.toNumber(), 11 + 1, "difficulty is not the expected one"); // # +1 since setInitialParent was called with imaginary block
        const averageChainWork = await dr.getAverageChainWork.call();
        assert.equal(averageChainWork.toNumber(), 10, "average chain work is not the expected one");
    });
});

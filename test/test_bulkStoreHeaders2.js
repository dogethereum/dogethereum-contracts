//const DogeRelay = artifacts.require('DogeRelayForTests');
const ScryptCheckerDummy = artifacts.require('ScryptCheckerDummy');
const utils = require('./utils');


contract.skip('test_bulkStoreHeaders2', (accounts) => {
  let dogeRelay;
  before(async () => {
    dogeRelay = await DogeRelay.new(1);
    const scryptChecker = await ScryptCheckerDummy.new(true);
    await dogeRelay.setScryptChecker(scryptChecker.address);
  });
  it("testDifficulty", async () => {
    // Dogecoin testnet
    const block739200Hash = "0x69404b833f190a1a29c32265ad73ea344ccaba82367be0d43d58a9eed2b8d357";
    await dogeRelay.setInitialParent(block739200Hash, 739200, 1, {from: accounts[0]});

    const { headers: rawHeaders, hashes: rawHashes } = await utils.parseDataFile('test/headers/elevenDogeTestnet.txt');

    const headers = `0x${rawHeaders.map(utils.addSizeToHeader).join('')}`;
    const hashes = `0x${rawHeaders.map(utils.calcHeaderPoW).join('')}`;

    const result = await dogeRelay.bulkStoreHeaders(headers, hashes, 11, {from: accounts[0]});
    //console.log(result.receipt.logs);

    const chainWork = await dogeRelay.getChainWork.call();
    assert.equal(chainWork.toNumber(), 11 + 1, "difficulty is not the expected one"); // # +1 since setInitialParent was called with imaginary block

    const averageChainWork = await dogeRelay.getAverageChainWork.call();
    assert.equal(averageChainWork.toNumber(), 10, "average chain work is not the expected one");
  });
});

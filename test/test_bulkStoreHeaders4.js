//const DogeRelay = artifacts.require('DogeRelayForTests');
const ScryptCheckerDummy = artifacts.require('ScryptCheckerDummy');
const utils = require('./utils');


contract.skip('test_bulkStoreHeaders4', (accounts) => {
  let dogeRelay;
  before(async () => {
    dogeRelay = await DogeRelay.new(1);
    const scryptChecker = await ScryptCheckerDummy.new(true);
    await dogeRelay.setScryptChecker(scryptChecker.address);
  });
  it("testDifficulty", async () => {
    // Dogecoin testnet
    const block145000Hash = "0x26d737ddcdaa35463e466ee870b0e75699bcffed1b3df720522b042020507c93";
    await dogeRelay.setInitialParent(block145000Hash, 145000, 1, {from: accounts[0]});

    const { headers: rawHeaders, hashes: rawHashes } = await utils.parseDataFile('test/headers/dogeTestnetDifficulty.txt');

    const headers = `0x${rawHeaders.map(utils.addSizeToHeader).join('')}`;
    const hashes = `0x${rawHeaders.map(utils.calcHeaderPoW).join('')}`;

    const result = await dogeRelay.bulkStoreHeaders(headers, hashes, 11, {from: accounts[0]});
    // console.log(result.receipt.logs);

    const chainWork = await dogeRelay.getChainWork.call();
    assert.equal(chainWork.toNumber(), 11 + 1, "difficulty is not the expected one"); // # +1 since setInitialParent was called with imaginary block

    const averageChainWork = await dogeRelay.getAverageChainWork.call();
  });
});

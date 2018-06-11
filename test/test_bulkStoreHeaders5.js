const DogeRelay = artifacts.require('DogeRelayForTests');
const ScryptCheckerDummy = artifacts.require('ScryptCheckerDummy');
const utils = require('./utils');


contract('test_bulkStoreHeaders5', (accounts) => {
  let dogeRelay;
  before(async () => {
    dogeRelay = await DogeRelay.new(1);
    const scryptChecker = await ScryptCheckerDummy.new(true);
    await dogeRelay.setScryptChecker(scryptChecker.address);
  });
  it("testDifficulty", async () => {
    // Dogecoin testnet
    const block160000Hash = "0x5a4df2c095676f3f4e064bb5973adc3bf615ece4288d9d6f6a18e4393742b0ec";
    await dogeRelay.setInitialParent(block160000Hash, 160000, 1, {from: accounts[0]});

    const { headers: rawHeaders, hashes: rawHashes } = await utils.parseDataFile('test/headers/dogeTestnetDifficulty160000.txt');

    const headers = `0x${rawHeaders.map(utils.addSizeToHeader).join('')}`;
    const hashes = `0x${rawHeaders.map(utils.calcHeaderPoW).join('')}`;

    const result = await dogeRelay.bulkStoreHeaders(headers, hashes, 11, {from: accounts[0]});
    // console.log(result.receipt.logs);

    const bestBlockHeight = await dogeRelay.getBestBlockHeight.call();
    assert.equal(bestBlockHeight.toNumber(), 160000 + 11, "getBestBlockHeight is not the expected one");
  });
});

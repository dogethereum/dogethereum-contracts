var DogeRelay = artifacts.require("./DogeRelayForTests.sol");
var DogeToken = artifacts.require("./token/DogeTokenForTests.sol");
var utils = require('./utils');


contract('testDogeTokenDoUnlockRequires', function(accounts) {
  let dogeToken;
  before(async () => {
      dogeToken = await DogeToken.deployed();
  });
  it('doUnlock fails when it should', async () => {
    const operatorPublicKeyHash = `0x4d905b4b815d483cdfabcd292c6f86509d0fad82`;
    await dogeToken.addOperatorSimple(operatorPublicKeyHash);

    await dogeToken.assign(accounts[0], 3000000000);
    const dogeAddress = "DHx8ZyJJuiFM5xAHFypfz1k6bd2X85xNMy";

    var didNotFail = false;

    try {
      await dogeToken.doUnlock(dogeAddress, 200000000, operatorPublicKeyHash);      
      didNotFail = true;
    } catch (ex) {}
    assert.isFalse(didNotFail, "unlock an amount below min value. Expected to fail, but it didn't.");

    try {
      await dogeToken.doUnlock(dogeAddress, 200000000000, operatorPublicKeyHash);
      didNotFail = true;
    } catch (ex) {}
    assert.isFalse(didNotFail, "unlock an amount greater than user value. Expected to fail, but it didn't.");

    try {
      await dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash);
      didNotFail = true;
    } catch (ex) {}
    assert.isFalse(didNotFail, "unlock where no utxos are available. Expected to fail, but it didn't.");

    await dogeToken.addUtxo(operatorPublicKeyHash, 100000000, 1, 10);
    try {
      await dogeToken.doUnlock(dogeAddress, 2500000000, operatorPublicKeyHash);
      didNotFail = true;
    } catch (ex) {}
    assert.isFalse(didNotFail, "unlock when available utxos does not cover value. Expected to fail, but it didn't.");


    for (i = 0; i < 9; i++) { 
      await dogeToken.addUtxo(operatorPublicKeyHash, 100000000, 1, 10);
    }
    try {
      await dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash)
      didNotFail = true;
    } catch (ex) {}
    assert.isFalse(didNotFail, "unlock when value to send is greater than fee. Expected to fail, but it didn't.");

  });
});

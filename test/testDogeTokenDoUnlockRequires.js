var DogeRelay = artifacts.require("./DogeRelayForTests.sol");
var DogeToken = artifacts.require("./token/DogeTokenForTests.sol");
var utils = require('./utils');


contract('testDogeTokenDoUnlockRequires', function(accounts) {
  let dogeToken;
  before(async () => {
      dogeToken = await DogeToken.deployed();
  });
  it('doUnlock fails when it should', async () => {

    await dogeToken.assign(accounts[0], 3000000000);
    const dogeAddress = "DHx8ZyJJuiFM5xAHFypfz1k6bd2X85xNMy";

    // Check unlock an amount below min value fails    
    await dogeToken.doUnlock(dogeAddress, 200000000);
    var unlockIdx = await dogeToken.unlockIdx();
    assert.equal(unlockIdx.toNumber(), 0, `Unlock was created`);    

    // Check unlock an amount greater than user value fails
    await dogeToken.doUnlock(dogeAddress, 200000000000);
    var unlockIdx = await dogeToken.unlockIdx();
    assert.equal(unlockIdx.toNumber(), 0, `Unlock was created`);    

    // Check there is at least 1 utxo available
    await dogeToken.doUnlock(dogeAddress, 1000000000);
    var unlockIdx = await dogeToken.unlockIdx();
    assert.equal(unlockIdx.toNumber(), 0, `Unlock was created`);    


    await dogeToken.addUtxo(100000000, 1, 10);

    // Check available utxos cover value
    await dogeToken.doUnlock(dogeAddress, 2500000000);
    var unlockIdx = await dogeToken.unlockIdx();
    assert.equal(unlockIdx.toNumber(), 0, `Unlock was created`);    

    for (i = 0; i < 9; i++) { 
      await dogeToken.addUtxo(100000000, 1, 10);
    }

    // Check value to send is greater than fee
    await dogeToken.doUnlock(dogeAddress, 1000000000);
    var unlockIdx = await dogeToken.unlockIdx();
    assert.equal(unlockIdx.toNumber(), 0, `Unlock was created`);    

  });
});

var DogeRelay = artifacts.require("./DogeRelayForTests.sol");
var DogeToken = artifacts.require("./token/DogeTokenForTests.sol");
var utils = require('./utils');


contract('testDogeTokenDoUnlock2', function(accounts) {
  let dogeToken;
  before(async () => {
      dogeToken = await DogeToken.deployed();
  });
  it('doUnlock whith multiple utxos', async () => {

    await dogeToken.assign(accounts[0], 5600000000);
    var balance = await dogeToken.balanceOf(accounts[0]);

    await dogeToken.addUtxo(400000000, 1, 1);
    await dogeToken.addUtxo(200000000, 2, 1);
    await dogeToken.addUtxo(600000000, 3, 1);
    await dogeToken.addUtxo(800000000, 4, 1);
    await dogeToken.addUtxo(900000000, 4, 1);
    await dogeToken.addUtxo(900000000, 4, 1);
    await dogeToken.addUtxo(900000000, 4, 1);
    await dogeToken.addUtxo(900000000, 4, 1);

    const dogeAddress = "DHx8ZyJJuiFM5xAHFypfz1k6bd2X85xNMy";

    // Unlock Request 1
    await dogeToken.doUnlock(dogeAddress, 1000000000).then(function(result) {
      //console.log(result.receipt.logs);
    });
    var unlockPendingInvestorProof = await dogeToken.getUnlocksPendingInvestorProof(1);
    //console.log(unlockPendingInvestorProof);
    assert.deepEqual(utils.bigNumberArrayToNumberArray(unlockPendingInvestorProof[4]), [0, 1, 2], `Unlock selectedUtxos are not the expected ones`);
    assert.equal(unlockPendingInvestorProof[5].toNumber(), 350000000, `Unlock fee is not the expected one`);
    balance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(balance, 4600000000, `DogeToken's ${accounts[0]} balance after unlock is not the expected one`);

    // Unlock Request 2
    await dogeToken.doUnlock(dogeAddress, 1500000000);
    var unlockPendingInvestorProof = await dogeToken.getUnlocksPendingInvestorProof(2);
    assert.deepEqual(utils.bigNumberArrayToNumberArray(unlockPendingInvestorProof[4]), [3, 4], `Unlock selectedUtxos are not the expected ones`);
    assert.equal(unlockPendingInvestorProof[5].toNumber(), 250000000, `Unlock fee is not the expected one`);
    balance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(balance, 3100000000, `DogeToken's ${accounts[0]} balance after unlock is not the expected one`);


  });
});

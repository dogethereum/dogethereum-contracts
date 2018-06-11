var DogeRelay = artifacts.require("./DogeRelayForTests.sol");
var DogeToken = artifacts.require("./token/DogeTokenForTests.sol");
var utils = require('./utils');


contract('testDogeTokenDoUnlock', function(accounts) {
  let dogeToken;
  before(async () => {
      dogeToken = await DogeToken.deployed();
  });
  it('doUnlock does not fail', async () => {
    const operatorPublicKeyHash = `0x4d905b4b815d483cdfabcd292c6f86509d0fad82`;
    await dogeToken.addOperatorSimple(operatorPublicKeyHash);

    await dogeToken.assign(accounts[0], 2000000000);
    var balance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(balance, 2000000000, `DogeToken's ${accounts[0]} balance is not the expected one`);

    await dogeToken.addUtxo(operatorPublicKeyHash, 2000000000, 1, 10);
    const utxo = await dogeToken.getUtxo(operatorPublicKeyHash, 0);
    assert.equal(utxo[0].toNumber(), 2000000000, `Utxo value is not the expected one`);

    const dogeAddress = "DHx8ZyJJuiFM5xAHFypfz1k6bd2X85xNMy";
    await dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash).then(function(result) {
      //console.log(result.receipt.logs);
    });

    const unlockPendingInvestorProof = await dogeToken.getUnlockPendingInvestorProof(0);
    //console.log(unlockPendingInvestorProof);
    assert.equal(unlockPendingInvestorProof[0], accounts[0], `Unlock from is not the expected one`);
    assert.equal(unlockPendingInvestorProof[1], dogeAddress, `Unlock doge address is not the expected one`);
    assert.equal(unlockPendingInvestorProof[2].toNumber(), 1000000000, `Unlock value is not the expected one`);
    assert.equal(unlockPendingInvestorProof[4][0].toNumber(), 0, `Unlock selectedUtxos is not the expected one`);
    assert.equal(unlockPendingInvestorProof[5].toNumber(), 150000000, `Unlock fee is not the expected one`);
    assert.equal(unlockPendingInvestorProof[6], operatorPublicKeyHash, `Unlock operatorPublicKeyHash is not the expected one`);

    balance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(balance, 1000000000, `DogeToken's ${accounts[0]} balance after unlock is not the expected one`);

  });
});

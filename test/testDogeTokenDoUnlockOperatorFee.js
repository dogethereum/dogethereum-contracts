var DogeToken = artifacts.require("./token/DogeTokenForTests.sol");
var utils = require('./utils');


contract('testDogeTokenDoUnlockOperatorFee', function(accounts) {
  let dogeToken;
  before(async () => {
      dogeToken = await DogeToken.deployed();
  });
  it('doUnlock pays operator fee', async () => {
    const operatorPublicKeyHash = `0x4d905b4b815d483cdfabcd292c6f86509d0fad82`;
    const operatorEthAddress = accounts[3];
    await dogeToken.addOperatorSimple(operatorPublicKeyHash, operatorEthAddress);

    await dogeToken.assign(accounts[0], 20000000000);
    var balance = await dogeToken.balanceOf(accounts[0]);
    assert.equal(balance, 20000000000, `DogeToken's ${accounts[0]} balance is not the expected one`);

    await dogeToken.addUtxo(operatorPublicKeyHash, 20000000000, 1, 10);
    const utxo = await dogeToken.getUtxo(operatorPublicKeyHash, 0);
    assert.equal(utxo[0].toNumber(), 20000000000, `Utxo value is not the expected one`);

    const dogeAddress = "DHx8ZyJJuiFM5xAHFypfz1k6bd2X85xNMy";
    await dogeToken.doUnlock(dogeAddress, 15000000000, operatorPublicKeyHash).then(function(result) {
      //console.log(result.receipt.logs);
    });

    const unlockPendingInvestorProof = await dogeToken.getUnlockPendingInvestorProof(0);
    assert.equal(unlockPendingInvestorProof[3].toNumber(), 150000000, `Unlock operator fee is not the expected one`);
    var operatorEthBalance = await dogeToken.balanceOf(operatorEthAddress);
    assert.equal(operatorEthBalance.toNumber(), 150000000, `DogeToken's operator balance after unlock is not the expected one`);
  });
});

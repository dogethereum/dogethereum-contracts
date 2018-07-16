//var DogeRelay = artifacts.require("./DogeRelayForTests.sol");
var DogeToken = artifacts.require("./token/DogeTokenForTests.sol");
var utils = require('./utils');


contract.skip('testDogeTokenDoUnlockRequires', function(accounts) {
  let dogeToken;
  before(async () => {
      dogeToken = await DogeToken.deployed();
  });
  it('doUnlock fails when it should', async () => {
    const operatorPublicKeyHash = `0x4d905b4b815d483cdfabcd292c6f86509d0fad82`;

    await dogeToken.assign(accounts[0], 3000000000);
    const dogeAddress = "DHx8ZyJJuiFM5xAHFypfz1k6bd2X85xNMy";


    // unlock an amount below min value.
    var doUnlockTxReceipt = await dogeToken.doUnlock(dogeAddress, 200000000, operatorPublicKeyHash);
    assert.equal(60080, doUnlockTxReceipt.logs[0].args.err, "Expected ERR_UNLOCK_MIN_UNLOCK_VALUE error");


    // unlock an amount greater than user value.
    doUnlockTxReceipt = await dogeToken.doUnlock(dogeAddress, 200000000000, operatorPublicKeyHash);
    assert.equal(60090, doUnlockTxReceipt.logs[0].args.err, "Expected ERR_UNLOCK_USER_BALANCE error");


    // unlock where operator was not created
    doUnlockTxReceipt = await dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash);
    assert.equal(60100, doUnlockTxReceipt.logs[0].args.err, "Expected ERR_UNLOCK_OPERATOR_NOT_CREATED error");

    // unlock where operator available balance is bellow requested value
    await dogeToken.addOperatorSimple(operatorPublicKeyHash);
    doUnlockTxReceipt = await dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash);
    assert.equal(60110, doUnlockTxReceipt.logs[0].args.err, "Expected ERR_UNLOCK_OPERATOR_BALANCE error");

    // unlock where no utxos are available. This is an unrealistic scenario since ERR_UNLOCK_OPERATOR_BALANCE should have been returned before.
    await dogeToken.addDogeAvailableBalance(operatorPublicKeyHash, 1000000000);
    doUnlockTxReceipt = await dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash);
    await dogeToken.subtractDogeAvailableBalance(operatorPublicKeyHash, 1000000000);
    assert.equal(60120, doUnlockTxReceipt.logs[0].args.err, "Expected ERR_UNLOCK_NO_AVAILABLE_UTXOS error");

    // unlock when available utxos does not cover value. This is an unrealistic scenario since ERR_UNLOCK_OPERATOR_BALANCE should have been returned before.
    await dogeToken.addUtxo(operatorPublicKeyHash, 100000000, 1, 10);
    await dogeToken.addDogeAvailableBalance(operatorPublicKeyHash, 2400000000);
    var doUnlockTxReceipt = await dogeToken.doUnlock(dogeAddress, 2500000000, operatorPublicKeyHash);
    await dogeToken.subtractDogeAvailableBalance(operatorPublicKeyHash, 2400000000);
    assert.equal(60130, doUnlockTxReceipt.logs[0].args.err, "Expected ERR_UNLOCK_UTXOS_VALUE_LESS_THAN_VALUE_TO_SEND error");

    // unlock when value to send is greater than fee
    for (i = 0; i < 9; i++) {
      await dogeToken.addUtxo(operatorPublicKeyHash, 100000000, 1, 10);
    }
    var doUnlockTxReceipt = await dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash)
    assert.equal(60140, doUnlockTxReceipt.logs[0].args.err, "Expected ERR_UNLOCK_VALUE_TO_SEND_LESS_THAN_FEE error");
  });
});

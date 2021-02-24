const hre = require("hardhat");

const deploy = require('../deploy');

const utils = require('./utils');


contract('testDogeTokenDoUnlockRequires', function(accounts) {
  let dogeToken;
  let snapshot;
  before(async () => {
    const dogethereum = await deploy.deployFixture(hre);
    dogeToken = dogethereum.dogeToken;
    snapshot = await hre.network.provider.request({method: "evm_snapshot", params: []});
  });
  after(async function() {
    await hre.network.provider.request({method: "evm_revert", params: [snapshot]});
  });

  // TODO: break up this test into several different tests
  // Convert this top level test into a describe?
  it('doUnlock fails when it should', async () => {
    const operatorPublicKeyHash = `0x4d905b4b815d483cdfabcd292c6f86509d0fad82`;

    await dogeToken.assign(accounts[0], 3000000000);
    const dogeAddress = utils.base58ToBytes20("DHx8ZyJJuiFM5xAHFypfz1k6bd2X85xNMy");


    // unlock an amount below min value.
    let doUnlockTxResponse = await dogeToken.doUnlock(dogeAddress, 200000000, operatorPublicKeyHash);
    let doUnlockTxReceipt = await doUnlockTxResponse.wait();
    assert.equal(60080, doUnlockTxReceipt.events[0].args.err, "Expected ERR_UNLOCK_MIN_UNLOCK_VALUE error");


    // unlock an amount greater than user value.
    doUnlockTxResponse = await dogeToken.doUnlock(dogeAddress, 200000000000, operatorPublicKeyHash);
    doUnlockTxReceipt = await doUnlockTxResponse.wait();
    assert.equal(60090, doUnlockTxReceipt.events[0].args.err, "Expected ERR_UNLOCK_USER_BALANCE error");


    // unlock where operator was not created
    doUnlockTxResponse = await dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash);
    doUnlockTxReceipt = await doUnlockTxResponse.wait();
    assert.equal(60100, doUnlockTxReceipt.events[0].args.err, "Expected ERR_UNLOCK_OPERATOR_NOT_CREATED error");

    // unlock where operator available balance is bellow requested value
    const operatorEthAddress = accounts[3];
    await dogeToken.addOperatorSimple(operatorPublicKeyHash, operatorEthAddress);
    doUnlockTxResponse = await dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash);
    doUnlockTxReceipt = await doUnlockTxResponse.wait();
    assert.equal(60110, doUnlockTxReceipt.events[0].args.err, "Expected ERR_UNLOCK_OPERATOR_BALANCE error");

    // unlock where no utxos are available. This is an unrealistic scenario since ERR_UNLOCK_OPERATOR_BALANCE should have been returned before.
    await dogeToken.addDogeAvailableBalance(operatorPublicKeyHash, 1000000000);
    doUnlockTxResponse = await dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash);
    doUnlockTxReceipt = await doUnlockTxResponse.wait();
    await dogeToken.subtractDogeAvailableBalance(operatorPublicKeyHash, 1000000000);
    assert.equal(60120, doUnlockTxReceipt.events[0].args.err, "Expected ERR_UNLOCK_NO_AVAILABLE_UTXOS error");

    // unlock when available utxos does not cover value. This is an unrealistic scenario since ERR_UNLOCK_OPERATOR_BALANCE should have been returned before.
    await dogeToken.addUtxo(operatorPublicKeyHash, 100000000, 1, 10);
    await dogeToken.addDogeAvailableBalance(operatorPublicKeyHash, 2400000000);
    doUnlockTxResponse = await dogeToken.doUnlock(dogeAddress, 2500000000, operatorPublicKeyHash);
    doUnlockTxReceipt = await doUnlockTxResponse.wait();
    await dogeToken.subtractDogeAvailableBalance(operatorPublicKeyHash, 2400000000);
    assert.equal(60130, doUnlockTxReceipt.events[0].args.err, "Expected ERR_UNLOCK_UTXOS_VALUE_LESS_THAN_VALUE_TO_SEND error");

    // unlock when value to send is greater than fee
    for (i = 0; i < 9; i++) {
      await dogeToken.addUtxo(operatorPublicKeyHash, 100000000, 1, 10);
    }
    doUnlockTxResponse = await dogeToken.doUnlock(dogeAddress, 1000000000, operatorPublicKeyHash)
    doUnlockTxReceipt = await doUnlockTxResponse.wait();
    assert.equal(60140, doUnlockTxReceipt.events[0].args.err, "Expected ERR_UNLOCK_VALUE_TO_SEND_LESS_THAN_FEE error");
  });
});

const DogeToken = artifacts.require("./token/DogeTokenForTests.sol");
const utils = require('./utils');
const BigNumber = require('bignumber.js');
const BN = require('bn.js');

contract('DogeToken - Operators', (accounts) => {
  const trustedDogeEthPriceOracle = accounts[0]; // Tell DogeToken to trust accounts[0] as a price oracle
  const trustedRelayerContract = accounts[0]; // Tell DogeToken to trust accounts[0] as it would be the relayer contract
  const collateralRatio = 2;

  const operatorPublicKeyHash = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
  const operatorPrivateKeyString = "105bd30419904ef409e9583da955037097f22b6b23c57549fe38ab8ffa9deaa3";
  const operatorEthAddress = accounts[1];

  async function sendAddOperator(dogeToken, wrongSignature) {
      var operatorSignItsEthAddressResult = utils.operatorSignItsEthAddress(operatorPrivateKeyString, operatorEthAddress);
      var operatorPublicKeyCompressedString = operatorSignItsEthAddressResult[0];
      var signature = operatorSignItsEthAddressResult[1];
      if (wrongSignature) {
        signature += "ff";
      }
      var addOperatorTxReceipt = await dogeToken.addOperator(operatorPublicKeyCompressedString, signature, {from: operatorEthAddress});
      return addOperatorTxReceipt;
  }


  describe('addOperator', () => {
    it('addOperator success', async () => {
      const dogeToken = await DogeToken.new(trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio);
      var addOperatorTxReceipt = await sendAddOperator(dogeToken);
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[0], operatorEthAddress, 'Operator not created');
      var operatorKeys = await dogeToken.operatorKeys(0);
      assert.equal(operatorKeys[0], operatorPublicKeyHash, 'operatorKeys[0] not what expected');
      assert.equal(operatorKeys[1], false, 'operatorKeys[1] not what expected');
      var operatorsLength = await dogeToken.getOperatorsLength();
      assert.equal(operatorsLength, 1, 'operatorsLength not what expected');
    });
    it('addOperator fail - try adding the same operator twice', async () => {
      const dogeToken = await DogeToken.new(trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio);
      var addOperatorTxReceipt = await sendAddOperator(dogeToken);
      addOperatorTxReceipt = await sendAddOperator(dogeToken);
      assert.equal(60015, addOperatorTxReceipt.logs[0].args.err, "Expected ERR_OPERATOR_ALREADY_CREATED error");
    });
    it('addOperator fail - wrong signature', async () => {
      const dogeToken = await DogeToken.new(trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio);
      var addOperatorTxReceipt = await sendAddOperator(dogeToken, true);
      assert.equal(60010, addOperatorTxReceipt.logs[0].args.err, "Expected ERR_OPERATOR_SIGNATURE error");
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[0], 0, 'Operator created');
    });
  });

  describe('addOperatorDeposit', () => {
    it('addOperatorDeposit success', async () => {
      const dogeToken = await DogeToken.new(trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio);
      await sendAddOperator(dogeToken);
      await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 1000000000000000000, from : operatorEthAddress});
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 1000000000000000000, 'Deposit not credited');
    });
    it('addOperatorDeposit fail - operator not created', async () => {
      const dogeToken = await DogeToken.new(trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio);
      var addOperatorDepositTxReceipt = await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 1000000000000000000, from : operatorEthAddress});
      assert.equal(60020, addOperatorDepositTxReceipt.logs[0].args.err, "Expected ERR_OPERATOR_NOT_CREATED_OR_WRONG_SENDER error");
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 0, 'Deposit credited');
    });
    it('addOperatorDeposit fail - wrong sender', async () => {
      const dogeToken = await DogeToken.new(trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio);
      await sendAddOperator(dogeToken);
      var addOperatorDepositTxReceipt = await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 1000000000000000000, from : accounts[0]});
      assert.equal(60020, addOperatorDepositTxReceipt.logs[0].args.err, "Expected ERR_OPERATOR_NOT_CREATED_OR_WRONG_SENDER error");
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 0, 'Deposit credited');
    });
  });

  describe('deleteOperator', () => {
    it('deleteOperator success', async () => {
      const dogeToken = await DogeToken.new(trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio);
      await sendAddOperator(dogeToken);
      await dogeToken.deleteOperator(operatorPublicKeyHash, {from : operatorEthAddress});
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[0], 0, 'Operator not deleted');
      var operatorKeys = await dogeToken.operatorKeys(0);
      assert.equal(operatorKeys[0], operatorPublicKeyHash, 'operatorKeys[0] not what expected');
      assert.equal(operatorKeys[1], true, 'operatorKeys[1] not what expected');
      var operatorsLength = await dogeToken.getOperatorsLength();
      assert.equal(operatorsLength, 1, 'operatorsLength not what expected');
    });
    it('deleteOperator fail - operator has eth balance', async () => {
      const dogeToken = await DogeToken.new(trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio);
      await sendAddOperator(dogeToken);
      await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 1000000000000000000, from : operatorEthAddress});
      var deleteOperatorTxReceipt = await dogeToken.deleteOperator(operatorPublicKeyHash, {from : operatorEthAddress});
      assert.equal(60030, deleteOperatorTxReceipt.logs[0].args.err, "Expected ERR_OPERATOR_HAS_BALANCE error");
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[0], operatorEthAddress, 'Operator deleted when failure was expected');
    });
  });


  describe('withdrawOperatorDeposit', () => {
    it('withdrawOperatorDeposit success - no utxo', async () => {
      const dogeToken = await DogeToken.new(trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio);
      await sendAddOperator(dogeToken);
      await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 1000000000000000000, from : operatorEthAddress});
      var operatorEthAddressBalanceBeforeWithdraw = await web3.eth.getBalance(operatorEthAddress);
      await dogeToken.setDogeEthPrice(1, {from : accounts[0]});
      var withdrawOperatorDepositTxReceipt = await dogeToken.withdrawOperatorDeposit(operatorPublicKeyHash, new BN("400000000000000000", 10), {from : operatorEthAddress});
      var operatorEthAddressBalanceAfterWithdraw = await web3.eth.getBalance(operatorEthAddress);
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 600000000000000000, 'Deposit not what expected');
      var tx = await web3.eth.getTransaction(withdrawOperatorDepositTxReceipt.tx);
      var txCost = withdrawOperatorDepositTxReceipt.receipt.cumulativeGasUsed * tx.gasPrice;
      assert.equal(new BN(operatorEthAddressBalanceAfterWithdraw, 10).sub(new BN(operatorEthAddressBalanceBeforeWithdraw, 10)).add(new BN(txCost, 10)).toString(10), "400000000000000000", 'balance not what expected');
    });
    it('withdrawOperatorDeposit success - with utxos', async () => {
      const dogeToken = await DogeToken.new(trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio);
      await sendAddOperator(dogeToken);
      await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 5000, from : operatorEthAddress});
      var operatorEthAddressBalanceBeforeWithdraw = await web3.eth.getBalance(operatorEthAddress);
      await dogeToken.setDogeEthPrice(3, {from : accounts[0]});
      await dogeToken.addUtxo(operatorPublicKeyHash, 400, 1, 1);
      var withdrawOperatorDepositTxReceipt = await dogeToken.withdrawOperatorDeposit(operatorPublicKeyHash, 100, {from : operatorEthAddress});
      var operatorEthAddressBalanceAfterWithdraw = await web3.eth.getBalance(operatorEthAddress);
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 4900, 'Deposit not what expected');
      var tx = await web3.eth.getTransaction(withdrawOperatorDepositTxReceipt.tx);
      var txCost = withdrawOperatorDepositTxReceipt.receipt.cumulativeGasUsed * tx.gasPrice;
      assert.equal(new BN(operatorEthAddressBalanceAfterWithdraw, 10).sub(new BN(operatorEthAddressBalanceBeforeWithdraw, 10)).add(new BN(txCost, 10)).toString(10), "100", 'balance not what expected');
    });
    it('withdrawOperatorDeposit fail - not enough balance', async () => {
      const dogeToken = await DogeToken.new(trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio);
      await sendAddOperator(dogeToken);
      await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 1000000000000000000, from : operatorEthAddress});
      await dogeToken.setDogeEthPrice(1, {from : accounts[0]});
      var withdrawOperatorDepositTxReceipt = await dogeToken.withdrawOperatorDeposit(operatorPublicKeyHash, new BN("2000000000000000000", 10), {from : operatorEthAddress});
      assert.equal(60040, withdrawOperatorDepositTxReceipt.logs[0].args.err, "Expected ERR_OPERATOR_WITHDRAWAL_NOT_ENOUGH_BALANCE error");
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 1000000000000000000, 'Operator eth balance was modified');
    });
    it('withdrawOperatorDeposit faril - deposit would be too low', async () => {
      const dogeToken = await DogeToken.new(trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio);
      await sendAddOperator(dogeToken);
      await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 5000, from : operatorEthAddress});
      await dogeToken.setDogeEthPrice(3, {from : accounts[0]});
      await dogeToken.addUtxo(operatorPublicKeyHash, 400, 1, 1);
      var withdrawOperatorDepositTxReceipt = await dogeToken.withdrawOperatorDeposit(operatorPublicKeyHash, 3000, {from : operatorEthAddress});
      assert.equal(60050, withdrawOperatorDepositTxReceipt.logs[0].args.err, "Expected ERR_OPERATOR_WITHDRAWAL_COLLATERAL_WOULD_BE_TOO_LOW error");
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 5000, 'Operator eth balance was modified');
    });
  });
});

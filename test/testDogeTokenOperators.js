const DogeToken = artifacts.require("./token/DogeTokenForTests.sol");
const utils = require('./utils');

contract('DogeToken - Operators', (accounts) => {
  const trustedDogeEthPriceOracle = accounts[0]; // Tell DogeToken to trust accounts[0] as a price oracle
  const trustedDogeRelay = accounts[0]; // Tell DogeToken to trust accounts[0] as it would be DogeRelay
  const collateralRatio = 2;

  const operatorPublicKeyHash = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
  const operatorPrivateKeyString = "105bd30419904ef409e9583da955037097f22b6b23c57549fe38ab8ffa9deaa3";
  const operatorEthAddress = web3.eth.accounts[1];  


  async function sendAddOperator(dogeToken, wrongSignature) {
      var operatorSignItsEthAddressResult = utils.operatorSignItsEthAddress(operatorPrivateKeyString, operatorEthAddress);
      var operatorPublicKeyString = operatorSignItsEthAddressResult[0];
      var signature = operatorSignItsEthAddressResult[1];
      if (wrongSignature) {
        signature += "ff";        
      }
      var addOperatorTxReceipt = await dogeToken.addOperator(operatorPublicKeyString, signature, {from: operatorEthAddress});
      return addOperatorTxReceipt;
  }

  
  describe('addOperator', () => {
    it('addOperator success', async () => {
      const dogeToken = await DogeToken.new(trustedDogeRelay, trustedDogeEthPriceOracle, collateralRatio);
      var addOperatorTxReceipt = await sendAddOperator(dogeToken);
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[0], operatorEthAddress, 'Operator not created');
    });
    it('addOperator wrong signature', async () => {
      const dogeToken = await DogeToken.new(trustedDogeRelay, trustedDogeEthPriceOracle, collateralRatio);
      var addOperatorTxReceipt = await sendAddOperator(dogeToken, true);
      assert.equal(60010, addOperatorTxReceipt.logs[0].args.err, "Expected ERR_OPERATOR_SIGNATURE error");
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[0], 0, 'Operator created');
    });
  });

  describe('addOperatorDeposit', () => {
    it('addOperatorDeposit success', async () => {
      const dogeToken = await DogeToken.new(trustedDogeRelay, trustedDogeEthPriceOracle, collateralRatio);
      await sendAddOperator(dogeToken);
      await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 1000000000000000000, from : operatorEthAddress});
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 1000000000000000000, 'Deposit not credited');
    });
    it('addOperatorDeposit operator not created', async () => {
      const dogeToken = await DogeToken.new(trustedDogeRelay, trustedDogeEthPriceOracle, collateralRatio);
      var addOperatorDepositTxReceipt = await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 1000000000000000000, from : operatorEthAddress});
      assert.equal(60020, addOperatorDepositTxReceipt.logs[0].args.err, "Expected ERR_OPERATOR_NOT_CREATED_OR_WRONG_SENDER error");
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 0, 'Deposit credited');
    });
    it('addOperatorDeposit wrong sender', async () => {
      const dogeToken = await DogeToken.new(trustedDogeRelay, trustedDogeEthPriceOracle, collateralRatio);
      await sendAddOperator(dogeToken);
      var addOperatorDepositTxReceipt = await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 1000000000000000000, from : accounts[0]});
      assert.equal(60020, addOperatorDepositTxReceipt.logs[0].args.err, "Expected ERR_OPERATOR_NOT_CREATED_OR_WRONG_SENDER error");
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 0, 'Deposit credited');
    });
  });  

  describe('deleteOperator', () => {
    it('deleteOperator success', async () => {
      const dogeToken = await DogeToken.new(trustedDogeRelay, trustedDogeEthPriceOracle, collateralRatio);
      await sendAddOperator(dogeToken);
      await dogeToken.deleteOperator(operatorPublicKeyHash, {from : operatorEthAddress});
      var operator = await dogeToken.operators(operatorPublicKeyHash);      
      assert.equal(operator[0], 0, 'Operator not deleted');
    });
    it('deleteOperator with eth balance', async () => {
      const dogeToken = await DogeToken.new(trustedDogeRelay, trustedDogeEthPriceOracle, collateralRatio);
      await sendAddOperator(dogeToken);
      await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 1000000000000000000, from : operatorEthAddress});
      var deleteOperatorTxReceipt = await dogeToken.deleteOperator(operatorPublicKeyHash, {from : operatorEthAddress});
      assert.equal(60030, deleteOperatorTxReceipt.logs[0].args.err, "Expected ERR_OPERATOR_HAS_BALANCE error");
      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[0], operatorEthAddress, 'Operator deleted when failure was expected');
    });
  });  

});

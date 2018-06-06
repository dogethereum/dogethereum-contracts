const DogeToken = artifacts.require("./token/DogeTokenForTests.sol");
const utils = require('./utils');

contract('DogeToken - Operators', (accounts) => {
  const trustedDogeEthPriceOracle = accounts[2]; // Tell DogeToken to trust accounts[0] as a price oracle
  const trustedDogeRelay = accounts[1]; // Tell DogeToken to trust accounts[0] as it would be DogeRelay
  const collateralRatio = 2;


  describe('addOperator', () => {
    //let dogeToken;
    //before(async () => {
    //  const trustedDogeEthPriceOracle = accounts[0]; // Tell DogeToken to trust accounts[0] as a price oracle
    //  const trustedDogeRelay = accounts[1]; // Tell DogeToken to trust accounts[0] as it would be DogeRelay
    //  const collateralRatio = 2;
    //  dogeToken = await DogeToken.new(trustedDogeRelay, trustedDogeEthPriceOracle, collateralRatio);
    //});

    it('addOperator simple', async () => {
      const dogeToken = await DogeToken.new(trustedDogeRelay, trustedDogeEthPriceOracle, collateralRatio);
      const operatorPublicKeyHash = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
      const operatorPrivateKeyString = "105bd30419904ef409e9583da955037097f22b6b23c57549fe38ab8ffa9deaa3";
      const operatorEthAddress = web3.eth.accounts[2];  
      var operatorSignItsEthAddressResult = utils.operatorSignItsEthAddress(operatorPrivateKeyString, operatorEthAddress)
      var operatorPublicKeyString = operatorSignItsEthAddressResult[0];
      var signature = operatorSignItsEthAddressResult[1];
      await dogeToken.addOperator(operatorPublicKeyString, signature, {from: operatorEthAddress});
      //await dt.addOperatorDeposit(operatorPublicKeyHash, {xvalue: 1000000000000000000, from : operatorEthAddress});

      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[0], operatorEthAddress, 'Operator not created');
    });
    it('addOperator wrong signature', async () => {
      const dogeToken = await DogeToken.new(trustedDogeRelay, trustedDogeEthPriceOracle, collateralRatio);
      const operatorPublicKeyHash = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
      const operatorPrivateKeyString = "105bd30419904ef409e9583da955037097f22b6b23c57549fe38ab8ffa9deaa3";
      const operatorEthAddress = web3.eth.accounts[2];  
      var operatorSignItsEthAddressResult = utils.operatorSignItsEthAddress(operatorPrivateKeyString, operatorEthAddress)
      var operatorPublicKeyString = operatorSignItsEthAddressResult[0];
      var signature = operatorSignItsEthAddressResult[1];
      // Adds an invalid byte to the signature
      signature += "ff";
      var addOperatorTxReceipt = await dogeToken.addOperator(operatorPublicKeyString, signature, {from: operatorEthAddress});
      assert.equal(60010, addOperatorTxReceipt.logs[0].args.err, "Expected ERR_OPERATOR_SIGNATURE error");

      var operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[0], 0, 'Operator created');
    });

  });
});

const hre = require("hardhat");

const deploy = require("../deploy");

const utils = require('./utils');

contract('DogeToken - Operators', (accounts) => {
  const trustedDogeEthPriceOracle = accounts[0]; // Tell DogeToken to trust accounts[0] as a price oracle
  const trustedRelayerContract = accounts[0]; // Tell DogeToken to trust accounts[0] as it would be the relayer contract
  const collateralRatio = 2;

  const operatorPublicKeyHash = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
  const operatorPrivateKeyString = "105bd30419904ef409e9583da955037097f22b6b23c57549fe38ab8ffa9deaa3";
  const operatorEthAddress = accounts[1];

  async function sendAddOperator(dogeToken, wrongSignature) {
    const operatorSignItsEthAddressResult = utils.operatorSignItsEthAddress(operatorPrivateKeyString, operatorEthAddress);
    const operatorPublicKeyCompressedString = operatorSignItsEthAddressResult[0];
    let signature = operatorSignItsEthAddressResult[1];
    if (wrongSignature) {
      signature += "ff";
    }
    const operatorSigner = await hre.ethers.getSigner(operatorEthAddress);
    const operatorDogeToken = dogeToken.connect(operatorSigner);
    const addOperatorTxResponse = await operatorDogeToken.addOperator(operatorPublicKeyCompressedString, signature);
    const addOperatorTxReceipt = await addOperatorTxResponse.wait();
    return addOperatorTxReceipt;
  }

  let dogeToken;
  let operatorDogeToken;

  beforeEach(async function() {
    const [signer] = await hre.ethers.getSigners();

    const { setLibrary } = await deploy.deployFixture(hre);
    dogeToken = await deploy.deployContract(
      "DogeTokenForTests",
      [trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio],
      hre,
      { signer, libraries: { Set: setLibrary.address } }
    );

    const operatorSigner = await hre.ethers.getSigner(operatorEthAddress);
    operatorDogeToken = dogeToken.connect(operatorSigner);
  });

  describe('addOperator', () => {

    it('addOperator success', async () => {
      await sendAddOperator(dogeToken);
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[0], operatorEthAddress, 'Operator not created');
      const operatorKeys = await dogeToken.operatorKeys(0);
      assert.equal(operatorKeys[0], operatorPublicKeyHash, 'operatorKeys[0] not what expected');
      assert.equal(operatorKeys[1], false, 'operatorKeys[1] not what expected');
      const operatorsLength = await dogeToken.getOperatorsLength();
      assert.equal(operatorsLength, 1, 'operatorsLength not what expected');
    });
    it('addOperator fail - try adding the same operator twice', async () => {
      await sendAddOperator(dogeToken);
      const addOperatorTxReceipt = await sendAddOperator(dogeToken);
      assert.equal(60015, addOperatorTxReceipt.events[0].args.err, "Expected ERR_OPERATOR_ALREADY_CREATED error");
    });
    it('addOperator fail - wrong signature', async () => {
      const addOperatorTxReceipt = await sendAddOperator(dogeToken, true);
      assert.equal(60010, addOperatorTxReceipt.events[0].args.err, "Expected ERR_OPERATOR_SIGNATURE error");
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[0], 0, 'Operator created');
    });
  });

  describe('addOperatorDeposit', () => {
    it('addOperatorDeposit success', async () => {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: "1000000000000000000"});
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], "1000000000000000000", 'Deposit not credited');
    });
    it('addOperatorDeposit fail - operator not created', async () => {
      const addOperatorDepositTxResponse = await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: "1000000000000000000"});
      const addOperatorDepositTxReceipt = await addOperatorDepositTxResponse.wait();
      assert.equal(60020, addOperatorDepositTxReceipt.events[0].args.err, "Expected ERR_OPERATOR_NOT_CREATED_OR_WRONG_SENDER error");
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 0, 'Deposit credited');
    });
    it('addOperatorDeposit fail - wrong sender', async () => {
      await sendAddOperator(dogeToken);
      const addOperatorDepositTxResponse = await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: "1000000000000000000"});
      const addOperatorDepositTxReceipt = await addOperatorDepositTxResponse.wait();
      assert.equal(60020, addOperatorDepositTxReceipt.events[0].args.err, "Expected ERR_OPERATOR_NOT_CREATED_OR_WRONG_SENDER error");
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 0, 'Deposit credited');
    });
  });

  describe('deleteOperator', () => {
    it('deleteOperator success', async () => {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.deleteOperator(operatorPublicKeyHash);
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[0], 0, 'Operator not deleted');
      const operatorKeys = await dogeToken.operatorKeys(0);
      assert.equal(operatorKeys[0], operatorPublicKeyHash, 'operatorKeys[0] not what expected');
      assert.equal(operatorKeys[1], true, 'operatorKeys[1] not what expected');
      const operatorsLength = await dogeToken.getOperatorsLength();
      assert.equal(operatorsLength, 1, 'operatorsLength not what expected');
    });
    it('deleteOperator fail - operator has eth balance', async () => {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: "1000000000000000000"});
      const deleteOperatorTxResponse = await operatorDogeToken.deleteOperator(operatorPublicKeyHash);
      const deleteOperatorTxReceipt = await deleteOperatorTxResponse.wait();
      assert.equal(60030, deleteOperatorTxReceipt.events[0].args.err, "Expected ERR_OPERATOR_HAS_BALANCE error");
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[0], operatorEthAddress, 'Operator deleted when failure was expected');
    });
  });


  describe('withdrawOperatorDeposit', () => {
    it('withdrawOperatorDeposit success - no utxo', async () => {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: "1000000000000000000"});
      const operatorEthAddressBalanceBeforeWithdraw = await hre.ethers.provider.getBalance(operatorEthAddress);
      await dogeToken.setDogeEthPrice(1);
      const withdrawOperatorDepositTxResponse = await operatorDogeToken.withdrawOperatorDeposit(operatorPublicKeyHash, "400000000000000000");
      const withdrawOperatorDepositTxReceipt = await withdrawOperatorDepositTxResponse.wait();
      const operatorEthAddressBalanceAfterWithdraw = await hre.ethers.provider.getBalance(operatorEthAddress);
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], "600000000000000000", 'Deposit not what expected');
      const txCost = withdrawOperatorDepositTxReceipt.cumulativeGasUsed.mul(withdrawOperatorDepositTxResponse.gasPrice);
      assert.equal(operatorEthAddressBalanceAfterWithdraw.sub(operatorEthAddressBalanceBeforeWithdraw).add(txCost).toString(10), "400000000000000000", 'balance not what expected');
    });
    it('withdrawOperatorDeposit success - with utxos', async () => {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 5000});
      const operatorEthAddressBalanceBeforeWithdraw = await hre.ethers.provider.getBalance(operatorEthAddress);
      await dogeToken.setDogeEthPrice(3);
      await dogeToken.addUtxo(operatorPublicKeyHash, 400, 1, 1);
      const withdrawOperatorDepositTxResponse = await operatorDogeToken.withdrawOperatorDeposit(operatorPublicKeyHash, 100);
      const withdrawOperatorDepositTxReceipt = await withdrawOperatorDepositTxResponse.wait();
      const operatorEthAddressBalanceAfterWithdraw = await hre.ethers.provider.getBalance(operatorEthAddress);
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 4900, 'Deposit not what expected');
      const txCost = withdrawOperatorDepositTxReceipt.cumulativeGasUsed.mul(withdrawOperatorDepositTxResponse.gasPrice);
      assert.equal(operatorEthAddressBalanceAfterWithdraw.sub(operatorEthAddressBalanceBeforeWithdraw).add(txCost).toString(10), "100", 'balance not what expected');
    });
    it('withdrawOperatorDeposit fail - not enough balance', async () => {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: "1000000000000000000"});
      await dogeToken.setDogeEthPrice(1);
      const withdrawOperatorDepositTxResponse = await operatorDogeToken.withdrawOperatorDeposit(operatorPublicKeyHash, "2000000000000000000");
      const withdrawOperatorDepositTxReceipt = await withdrawOperatorDepositTxResponse.wait();
      assert.equal(60040, withdrawOperatorDepositTxReceipt.events[0].args.err, "Expected ERR_OPERATOR_WITHDRAWAL_NOT_ENOUGH_BALANCE error");
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], "1000000000000000000", 'Operator eth balance was modified');
    });
    it('withdrawOperatorDeposit fail - deposit would be too low', async () => {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {value: 5000});
      await dogeToken.setDogeEthPrice(3);
      await dogeToken.addUtxo(operatorPublicKeyHash, 400, 1, 1);
      const withdrawOperatorDepositTxResponse = await operatorDogeToken.withdrawOperatorDeposit(operatorPublicKeyHash, 3000);
      const withdrawOperatorDepositTxReceipt = await withdrawOperatorDepositTxResponse.wait();
      assert.equal(60050, withdrawOperatorDepositTxReceipt.events[0].args.err, "Expected ERR_OPERATOR_WITHDRAWAL_COLLATERAL_WOULD_BE_TOO_LOW error");
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator[4], 5000, 'Operator eth balance was modified');
    });
  });
});

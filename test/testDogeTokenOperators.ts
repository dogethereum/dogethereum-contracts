import hre from "hardhat";
import { assert } from "chai";
import type { Contract, ContractTransaction } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import {
  deployFixture,
  deployToken,
  deployOracleMock,
  TokenOptions,
} from "../deploy";

import {
  expectFailure,
  isolateTests,
  isolateEachTest,
  operatorSignItsEthAddress,
} from "./utils";

describe("DogeToken - Operators", function () {
  const initialDogeUsdPrice = 100;
  // This is not a safe integer
  const initialEthUsdPrice = `1${"0".repeat(18)}`;

  let dogeUsdPriceOracle: Contract;
  let ethUsdPriceOracle: Contract;
  let trustedRelayerContract: string;
  const tokenOptions: TokenOptions = {
    lockCollateralRatio: "2000",
    liquidationThresholdCollateralRatio: "1500",
    unlockEthereumTimeGracePeriod: 4 * 60 * 60,
    unlockSuperblocksHeightGracePeriod: 4,
  };

  let operatorSigner: SignerWithAddress;
  const operatorPublicKeyHash = "0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6";
  const operatorPrivateKeyString =
    "105bd30419904ef409e9583da955037097f22b6b23c57549fe38ab8ffa9deaa3";

  isolateTests();
  isolateEachTest();

  async function sendAddOperator(dogeToken: Contract, wrongSignature = false) {
    const operatorSignItsEthAddressResult = operatorSignItsEthAddress(
      operatorPrivateKeyString,
      operatorSigner.address
    );
    const operatorPublicKeyCompressedString =
      operatorSignItsEthAddressResult[0];
    let signature = operatorSignItsEthAddressResult[1];
    if (wrongSignature) {
      signature += "ff";
    }
    const operatorDogeToken = dogeToken.connect(operatorSigner);
    const addOperatorTxResponse: ContractTransaction = await operatorDogeToken.addOperator(
      operatorPublicKeyCompressedString,
      signature
    );
    const addOperatorTxReceipt = await addOperatorTxResponse.wait();
    return addOperatorTxReceipt;
  }

  let dogeToken: Contract;
  let operatorDogeToken: Contract;

  before(async function () {
    const [signer, opSigner] = await hre.ethers.getSigners();
    // Tell DogeToken to trust the first account as a price oracle and relayer contract
    trustedRelayerContract = signer.address;

    const { superblockClaims } = await deployFixture(hre);

    dogeUsdPriceOracle = await deployOracleMock(
      hre,
      initialDogeUsdPrice,
      signer,
      0
    );
    ethUsdPriceOracle = await deployOracleMock(
      hre,
      initialEthUsdPrice,
      signer,
      0
    );

    const dogeTokenSystem = await deployToken(
      hre,
      "DogeTokenForTests",
      signer,
      dogeUsdPriceOracle.address,
      ethUsdPriceOracle.address,
      trustedRelayerContract,
      superblockClaims.address,
      tokenOptions
    );
    dogeToken = dogeTokenSystem.dogeToken.contract;

    operatorSigner = opSigner;
    operatorDogeToken = dogeToken.connect(opSigner);
  });

  describe("addOperator", function () {
    it("addOperator success", async function () {
      await sendAddOperator(dogeToken);
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(
        operator.ethAddress,
        operatorSigner.address,
        "Operator not created"
      );
      const operatorKey = await dogeToken.operatorKeys(0);
      assert.equal(
        operatorKey.key,
        operatorPublicKeyHash,
        "operatorKey.key not what expected"
      );
      assert.isFalse(operatorKey.deleted, "operator key is deleted");
      const operatorsLength = await dogeToken.getOperatorsLength();
      assert.equal(operatorsLength, 1, "operatorsLength not what expected");
    });

    it("addOperator fail - try adding the same operator twice", async function () {
      await sendAddOperator(dogeToken);
      await expectFailure(
        () => sendAddOperator(dogeToken),
        (error) => {
          assert.include(error.message, "Operator already created");
        }
      );
    });

    it("addOperator fail - wrong signature", async () => {
      await expectFailure(
        () => sendAddOperator(dogeToken, true),
        (error) => {
          assert.include(error.message, "Bad operator signature");
        }
      );
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(
        operator.ethAddress,
        0,
        "Operator created with a bad signature"
      );
    });
  });

  describe("addOperatorDeposit", function () {
    it("addOperatorDeposit success", async function () {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {
        value: "1000000000000000000",
      });
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(
        operator.ethBalance.toString(),
        "1000000000000000000",
        "Deposit not credited"
      );
    });

    it("addOperatorDeposit fail - operator not created", async function () {
      const addOperatorDepositTxResponse = await operatorDogeToken.addOperatorDeposit(
        operatorPublicKeyHash,
        { value: "1000000000000000000" }
      );
      const addOperatorDepositTxReceipt = await addOperatorDepositTxResponse.wait();
      assert.equal(
        60020,
        addOperatorDepositTxReceipt.events[0].args.err,
        "Expected ERR_OPERATOR_NOT_CREATED_OR_WRONG_SENDER error"
      );
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator.ethBalance, 0, "Deposit credited");
    });

    it("addOperatorDeposit fail - wrong sender", async function () {
      await sendAddOperator(dogeToken);
      const addOperatorDepositTxResponse = await dogeToken.addOperatorDeposit(
        operatorPublicKeyHash,
        { value: "1000000000000000000" }
      );
      const addOperatorDepositTxReceipt = await addOperatorDepositTxResponse.wait();
      assert.equal(
        60020,
        addOperatorDepositTxReceipt.events[0].args.err,
        "Expected ERR_OPERATOR_NOT_CREATED_OR_WRONG_SENDER error"
      );
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator.ethBalance, 0, "Deposit credited");
    });
  });

  describe("deleteOperator", function () {
    it("deleteOperator success", async function () {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.deleteOperator(operatorPublicKeyHash);
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator.ethAddress, 0, "Operator not deleted");
      const operatorKey = await dogeToken.operatorKeys(0);
      assert.equal(
        operatorKey.key,
        operatorPublicKeyHash,
        "operatorKey.key not what expected"
      );
      assert.isTrue(operatorKey.deleted, "operator key is not deleted");
      const operatorsLength = await dogeToken.getOperatorsLength();
      assert.equal(operatorsLength, 1, "operatorsLength not what expected");
    });

    it("deleteOperator fail - operator has eth balance", async function () {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {
        value: "1000000000000000000",
      });
      const deleteOperatorTxResponse = await operatorDogeToken.deleteOperator(
        operatorPublicKeyHash
      );
      const deleteOperatorTxReceipt = await deleteOperatorTxResponse.wait();
      assert.equal(
        60030,
        deleteOperatorTxReceipt.events[0].args.err,
        "Expected ERR_OPERATOR_HAS_BALANCE error"
      );
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(
        operator.ethAddress,
        operatorSigner.address,
        "Operator deleted when failure was expected"
      );
    });
  });

  describe("withdrawOperatorDeposit", function () {
    it("withdrawOperatorDeposit success - no utxo", async function () {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {
        value: "1000000000000000000",
      });
      const operatorEthAddressBalanceBeforeWithdraw = await hre.ethers.provider.getBalance(
        operatorSigner.address
      );
      await dogeUsdPriceOracle.setPrice(1);
      const withdrawOperatorDepositTxResponse = await operatorDogeToken.withdrawOperatorDeposit(
        operatorPublicKeyHash,
        "400000000000000000"
      );
      const withdrawOperatorDepositTxReceipt = await withdrawOperatorDepositTxResponse.wait();
      const operatorEthAddressBalanceAfterWithdraw = await hre.ethers.provider.getBalance(
        operatorSigner.address
      );
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(
        operator.ethBalance,
        "600000000000000000",
        "Deposit not what expected"
      );
      const txCost = withdrawOperatorDepositTxReceipt.cumulativeGasUsed.mul(
        withdrawOperatorDepositTxResponse.gasPrice
      );
      assert.equal(
        operatorEthAddressBalanceAfterWithdraw
          .sub(operatorEthAddressBalanceBeforeWithdraw)
          .add(txCost)
          .toString(),
        "400000000000000000",
        "balance not what expected"
      );
    });

    it("withdrawOperatorDeposit success - with utxos", async function () {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {
        value: 5000,
      });
      const operatorEthAddressBalanceBeforeWithdraw = await hre.ethers.provider.getBalance(
        operatorSigner.address
      );
      await dogeUsdPriceOracle.setPrice(3);
      await dogeToken.addUtxo(operatorPublicKeyHash, 400, 1, 1);
      const withdrawOperatorDepositTxResponse = await operatorDogeToken.withdrawOperatorDeposit(
        operatorPublicKeyHash,
        100
      );
      const withdrawOperatorDepositTxReceipt = await withdrawOperatorDepositTxResponse.wait();
      const operatorEthAddressBalanceAfterWithdraw = await hre.ethers.provider.getBalance(
        operatorSigner.address
      );
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(operator.ethBalance, 4900, "Deposit not what expected");
      const txCost = withdrawOperatorDepositTxReceipt.cumulativeGasUsed.mul(
        withdrawOperatorDepositTxResponse.gasPrice
      );
      assert.equal(
        operatorEthAddressBalanceAfterWithdraw
          .sub(operatorEthAddressBalanceBeforeWithdraw)
          .add(txCost)
          .toString(),
        "100",
        "balance not what expected"
      );
    });

    it("withdrawOperatorDeposit fail - not enough balance", async function () {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {
        value: "1000000000000000000",
      });
      await dogeUsdPriceOracle.setPrice(1);
      const withdrawOperatorDepositTxResponse = await operatorDogeToken.withdrawOperatorDeposit(
        operatorPublicKeyHash,
        "2000000000000000000"
      );
      const withdrawOperatorDepositTxReceipt = await withdrawOperatorDepositTxResponse.wait();
      assert.equal(
        60040,
        withdrawOperatorDepositTxReceipt.events[0].args.err,
        "Expected ERR_OPERATOR_WITHDRAWAL_NOT_ENOUGH_BALANCE error"
      );
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(
        operator.ethBalance,
        "1000000000000000000",
        "Operator eth balance was modified"
      );
    });

    it("withdrawOperatorDeposit fail - deposit would be too low", async function () {
      await sendAddOperator(dogeToken);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {
        value: 5000,
      });
      await dogeUsdPriceOracle.setPrice(3);
      await dogeToken.addUtxo(operatorPublicKeyHash, 400, 1, 1);
      const withdrawOperatorDepositTxResponse = await operatorDogeToken.withdrawOperatorDeposit(
        operatorPublicKeyHash,
        3000
      );
      const withdrawOperatorDepositTxReceipt = await withdrawOperatorDepositTxResponse.wait();
      assert.equal(
        60050,
        withdrawOperatorDepositTxReceipt.events[0].args.err,
        "Expected ERR_OPERATOR_WITHDRAWAL_COLLATERAL_WOULD_BE_TOO_LOW error"
      );
      const operator = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(
        operator.ethBalance,
        5000,
        "Operator eth balance was modified"
      );
    });
  });

  describe("reportOperatorUnsafeCollateral", function () {
    it("reporting an undercollateralized operator should liquidate her ether", async function () {
      await dogeToken.addOperatorSimple(
        operatorPublicKeyHash,
        operatorSigner.address
      );
      const utxoValue = 10_000_000;
      await dogeToken.addUtxo(operatorPublicKeyHash, utxoValue, 1, 1);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {
        value: 1,
      });

      const tx: ContractTransaction = await dogeToken.reportOperatorUnsafeCollateral(
        operatorPublicKeyHash
      );
      const receipt = await tx.wait();
      const liquidationEvents = receipt.events!.filter(({ event }) => {
        return event === "OperatorLiquidated";
      });

      assert.lengthOf(
        liquidationEvents,
        1,
        "Expected the operator to be liquidated."
      );
    });

    it("reporting a sufficiently collateralized operator should fail", async function () {
      await dogeToken.addOperatorSimple(
        operatorPublicKeyHash,
        operatorSigner.address
      );
      const utxoValue = 10_000_000;
      await dogeToken.addUtxo(operatorPublicKeyHash, utxoValue, 1, 1);
      await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {
        value: "100000000000000000000",
      });

      await expectFailure(
        () => dogeToken.reportOperatorUnsafeCollateral(operatorPublicKeyHash),
        (error) => {
          assert.include(
            error.message,
            "operator has enough collateral to be considered safe"
          );
        }
      );
    });
  });
});

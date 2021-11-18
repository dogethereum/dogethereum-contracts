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
  blockchainTimeoutSeconds,
  expectFailure,
  getEvents,
  isolateTests,
  isolateEachTest,
} from "./utils";

describe("DogeToken - Collateral auctions", function () {
  const initialDogeUsdPrice = 100;
  // This is not a safe integer
  const initialEthUsdPrice = `1${"0".repeat(18)}`;

  let dogeUsdPriceOracle: Contract;
  let ethUsdPriceOracle: Contract;
  const tokenOptions: TokenOptions = {
    lockCollateralRatio: "2000",
    liquidationThresholdCollateralRatio: "1500",
    unlockEthereumTimeGracePeriod: 4 * 60 * 60,
    unlockSuperblocksHeightGracePeriod: 4,
  };

  let operatorSigner: SignerWithAddress;
  const operatorPublicKeyHash = "0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6";
  // const operatorPrivateKeyString =
  //   "105bd30419904ef409e9583da955037097f22b6b23c57549fe38ab8ffa9deaa3";
  const operatorDeposit = 10 ** 9;

  let userASigner: SignerWithAddress;
  let userBSigner: SignerWithAddress;

  isolateTests();
  isolateEachTest();

  let dogeToken: Contract;
  let operatorDogeToken: Contract;
  let userAdogeToken: Contract;
  let userBdogeToken: Contract;

  before(async function () {
    const [
      signer,
      opSigner,
      thirdSigner,
      fourthSigner,
    ] = await hre.ethers.getSigners();

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
      signer.address,
      superblockClaims.address,
      tokenOptions
    );
    dogeToken = dogeTokenSystem.dogeToken.contract;

    operatorSigner = opSigner;
    operatorDogeToken = dogeToken.connect(opSigner);

    userASigner = thirdSigner;
    userAdogeToken = dogeToken.connect(userASigner);
    userBSigner = fourthSigner;
    userBdogeToken = dogeToken.connect(userBSigner);

    await dogeToken.addOperatorSimple(
      operatorPublicKeyHash,
      operatorSigner.address
    );
    const utxoValue = 100_000_000;
    await dogeToken.addUtxo(operatorPublicKeyHash, utxoValue, 1, 1);
    await operatorDogeToken.addOperatorDeposit(operatorPublicKeyHash, {
      value: operatorDeposit,
    });

    const tx: ContractTransaction = await dogeToken.reportOperatorUnsafeCollateral(
      operatorPublicKeyHash
    );

    const { events: liquidationEvents } = await getEvents(
      tx,
      "OperatorLiquidated"
    );

    assert.lengthOf(
      liquidationEvents,
      1,
      "Expected the operator to be liquidated."
    );
  });

  describe("Auction bidding", function () {
    it("bidding in an auction with no bids is successful", async function () {
      const tokenAmount = 100_000;
      await dogeToken.assign(userASigner.address, tokenAmount);

      const tx: ContractTransaction = await userAdogeToken.liquidationBid(
        operatorPublicKeyHash,
        tokenAmount
      );
      const { events: liquidationBids } = await getEvents(tx, "LiquidationBid");

      assert.lengthOf(
        liquidationBids,
        1,
        "Expected to observe a succesful bid."
      );

      const { auction } = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(auction.bestBidder, userASigner.address);
      assert.equal(auction.bestBid, tokenAmount);
    });

    it("bidding higher in an auction with a bid is successful", async function () {
      const tokenAmount = 100_000;
      await dogeToken.assign(userASigner.address, tokenAmount);
      const tokenAmount2 = 1_000_000;
      await dogeToken.assign(userBSigner.address, tokenAmount2);

      let tx: ContractTransaction = await userAdogeToken.liquidationBid(
        operatorPublicKeyHash,
        tokenAmount
      );
      let { events: liquidationBids } = await getEvents(tx, "LiquidationBid");

      assert.lengthOf(
        liquidationBids,
        1,
        "Expected to observe a succesful bid."
      );

      tx = await userBdogeToken.liquidationBid(
        operatorPublicKeyHash,
        tokenAmount2
      );
      ({ events: liquidationBids } = await getEvents(tx, "LiquidationBid"));

      assert.lengthOf(
        liquidationBids,
        1,
        "Expected to observe a succesful bid."
      );

      const { auction } = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(auction.bestBidder, userBSigner.address);
      assert.equal(auction.bestBid, tokenAmount2);
    });

    it("bidding lower in an auction with a bid fails", async function () {
      const tokenAmount = 100_000;
      await dogeToken.assign(userASigner.address, tokenAmount);
      const tokenAmount2 = 10_000;
      await dogeToken.assign(userBSigner.address, tokenAmount2);

      const tx: ContractTransaction = await userAdogeToken.liquidationBid(
        operatorPublicKeyHash,
        tokenAmount
      );
      const { events: liquidationBids } = await getEvents(tx, "LiquidationBid");

      assert.lengthOf(
        liquidationBids,
        1,
        "Expected to observe a succesful bid."
      );

      await expectFailure(
        () =>
          userBdogeToken.liquidationBid(operatorPublicKeyHash, tokenAmount2),
        (error) => {
          assert.include(error.message, "bid must be higher than the best bid");
        }
      );
    });

    it("bidding the same value in an auction with a bid fails", async function () {
      const tokenAmount = 100_000;
      await dogeToken.assign(userASigner.address, tokenAmount);
      await dogeToken.assign(userBSigner.address, tokenAmount);

      const tx: ContractTransaction = await userAdogeToken.liquidationBid(
        operatorPublicKeyHash,
        tokenAmount
      );
      const { events: liquidationBids } = await getEvents(tx, "LiquidationBid");

      assert.lengthOf(
        liquidationBids,
        1,
        "Expected to observe a succesful bid."
      );

      await expectFailure(
        () => userBdogeToken.liquidationBid(operatorPublicKeyHash, tokenAmount),
        (error) => {
          assert.include(error.message, "bid must be higher than the best bid");
        }
      );
    });
  });

  describe("Auction closing", function () {
    it("closing an auction with a bid after enough time has passed", async function () {
      const tokenAmount = 100_000;
      await dogeToken.assign(userASigner.address, tokenAmount);

      await userAdogeToken.liquidationBid(operatorPublicKeyHash, tokenAmount);

      await blockchainTimeoutSeconds(2 * 60 * 60 + 1);

      const preBalance = await userASigner.getBalance();

      const closeTx: ContractTransaction = await dogeToken.closeLiquidationAuction(
        operatorPublicKeyHash
      );
      const { events: closeEvents } = await getEvents(
        closeTx,
        "OperatorCollateralAuctioned"
      );

      assert.lengthOf(closeEvents, 1, "Expected the auction to close.");

      const postBalance = await userASigner.getBalance();

      assert.equal(
        preBalance.add(operatorDeposit).toString(),
        postBalance.toString()
      );

      const { ethBalance } = await dogeToken.operators(operatorPublicKeyHash);
      assert.equal(ethBalance.toString(), "0");
    });

    it("closing before enough time has passed should fail", async function () {
      const tokenAmount = 100_000;
      await dogeToken.assign(userASigner.address, tokenAmount);

      await userAdogeToken.liquidationBid(operatorPublicKeyHash, tokenAmount);

      await expectFailure(
        () => dogeToken.closeLiquidationAuction(operatorPublicKeyHash),
        (error) => {
          assert.include(
            error.message,
            "auction can't close before the minimum time window is expired"
          );
        }
      );
    });

    it("closing without a bid should fail", async function () {
      await blockchainTimeoutSeconds(2 * 60 * 60 + 1);

      await expectFailure(
        () => dogeToken.closeLiquidationAuction(operatorPublicKeyHash),
        (error) => {
          assert.include(
            error.message,
            "auction can't be closed without a bid"
          );
        }
      );
    });
  });
});

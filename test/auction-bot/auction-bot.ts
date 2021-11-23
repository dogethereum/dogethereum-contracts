import { assert } from "chai";
import type { Contract } from "ethers";
import hre from "hardhat";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { Config } from "../../auction-bot/config";
import { AuctionBot } from "../../auction-bot/main";
import {
  deployFixture,
  deployOracleMock,
  deployToken,
  TokenOptions,
} from "../../deploy";
import {
  blockchainTimeoutSeconds,
  mineBlocks,
  isolateEachTest,
  isolateTests,
} from "../utils";

describe("Auction bot", function () {
  isolateTests();
  isolateEachTest();

  let deploySigner: SignerWithAddress;
  let collateralBuyer: SignerWithAddress;
  let competitor: SignerWithAddress;
  let operatorSigner: SignerWithAddress;
  const operatorPublicKeyHash = "0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6";
  const operatorDeposit = 10 ** 9;

  let dogeToken: Contract;
  let dogeUsdPriceOracle: Contract;
  let ethUsdPriceOracle: Contract;

  const tokenOptions: TokenOptions = {
    lockCollateralRatio: "2000",
    liquidationThresholdCollateralRatio: "1500",
    unlockEthereumTimeGracePeriod: 4 * 60 * 60,
    unlockSuperblocksHeightGracePeriod: 4,
  };
  const bidAmount = "10000000";

  const initialDogeUsdPrice = 100;
  // This is not a safe integer
  const initialEthUsdPrice = `1${"0".repeat(18)}`;

  before(async function () {
    [
      deploySigner,
      operatorSigner,
      collateralBuyer,
      competitor,
    ] = await hre.ethers.getSigners();

    const { superblockClaims } = await deployFixture(hre);

    dogeUsdPriceOracle = await deployOracleMock(
      hre,
      initialDogeUsdPrice,
      deploySigner,
      0
    );
    ethUsdPriceOracle = await deployOracleMock(
      hre,
      initialEthUsdPrice,
      deploySigner,
      0
    );

    const dogeTokenSystem = await deployToken(
      hre,
      "DogeTokenForTests",
      deploySigner,
      dogeUsdPriceOracle.address,
      ethUsdPriceOracle.address,
      deploySigner.address,
      superblockClaims.address,
      tokenOptions
    );
    dogeToken = dogeTokenSystem.dogeToken.contract;

    await dogeToken.addOperatorSimple(
      operatorPublicKeyHash,
      operatorSigner.address
    );
    const utxoValue = 100_000_000;
    await dogeToken.addUtxo(operatorPublicKeyHash, utxoValue, 1, 1);
    await dogeToken
      .connect(operatorSigner)
      .addOperatorDeposit(operatorPublicKeyHash, {
        value: operatorDeposit,
      });
    const tokenBalance = hre.ethers.BigNumber.from(bidAmount).mul(10);
    await dogeToken.assign(collateralBuyer.address, tokenBalance);
    await dogeToken.assign(competitor.address, tokenBalance);
  });

  function testingConfig(config: Partial<Config> = {}): Config {
    const defaultConfig: Config = {
      indexerId: 0,
      auctionAddress: dogeToken.address,
      bidAmount,
      numberOfConfirmations: 6,
      startingBlock: "latest",
      sequelizeOptions: {
        logging: false,
        dialect: "sqlite",
        storage: ":memory:",
      },
    };
    return { ...defaultConfig, ...config };
  }

  describe("Init", function () {
    it("Launch simple bot", async function () {
      const config = testingConfig();

      await AuctionBot.create(collateralBuyer, config, hre.ethers);
    });

    it("Perform single step on empty blockchain", async function () {
      const config = testingConfig();

      const bot = await AuctionBot.create(collateralBuyer, config, hre.ethers);
      await bot.processNextBlocks();

      const unindexedBlockNumber = await bot.getFirstUnindexedBlockNumber();
      const blockNumber = await hre.ethers.provider.getBlockNumber();
      assert.equal(blockNumber + 1, unindexedBlockNumber);
    });

    it("Perform enough steps to consume small non-empty blockchain", async function () {
      const config = testingConfig({
        startingBlock: 0,
      });

      const bot = await AuctionBot.create(collateralBuyer, config, hre.ethers);
      await bot.processNextBlocks();
      await bot.processNextBlocks();

      const unindexedBlockNumber = await bot.getFirstUnindexedBlockNumber();
      const blockNumber = await hre.ethers.provider.getBlockNumber();
      assert.equal(blockNumber + 1, unindexedBlockNumber);
    });
  });

  describe("Auction participation", function () {
    it("Bid when an operator was liquidated", async function () {
      const config = testingConfig();
      const bot = await AuctionBot.create(collateralBuyer, config, hre.ethers);

      await dogeToken.reportOperatorUnsafeCollateral(operatorPublicKeyHash);
      const preBlockNumber = await hre.ethers.provider.getBlockNumber();

      await bot.processNextBlocks();
      const postBlockNumber = await hre.ethers.provider.getBlockNumber();

      const bidFilter = dogeToken.filters.LiquidationBid();
      const bidEvents = await dogeToken.queryFilter(
        bidFilter,
        preBlockNumber,
        postBlockNumber
      );
      assert.lengthOf(bidEvents, 1);
    });

    it("Avoids bidding when there's a better bid", async function () {
      const config = testingConfig();
      const bot = await AuctionBot.create(collateralBuyer, config, hre.ethers);

      await dogeToken.reportOperatorUnsafeCollateral(operatorPublicKeyHash);
      const preBlockNumber = await hre.ethers.provider.getBlockNumber();

      const biggerBid = hre.ethers.BigNumber.from(bidAmount).mul(2);
      await dogeToken
        .connect(competitor)
        .liquidationBid(operatorPublicKeyHash, biggerBid);

      await bot.processNextBlocks();
      const postBlockNumber = await hre.ethers.provider.getBlockNumber();

      const bidFilter = dogeToken.filters.LiquidationBid();
      const bidEvents = await dogeToken.queryFilter(
        bidFilter,
        preBlockNumber,
        postBlockNumber
      );
      assert.lengthOf(bidEvents, 1);
    });

    it("Avoids bidding when there's an equivalent bid", async function () {
      const config = testingConfig();
      const bot = await AuctionBot.create(collateralBuyer, config, hre.ethers);

      await dogeToken.reportOperatorUnsafeCollateral(operatorPublicKeyHash);
      const preBlockNumber = await hre.ethers.provider.getBlockNumber();

      const biggerBid = hre.ethers.BigNumber.from(bidAmount);
      await dogeToken
        .connect(competitor)
        .liquidationBid(operatorPublicKeyHash, biggerBid);

      await bot.processNextBlocks();
      const postBlockNumber = await hre.ethers.provider.getBlockNumber();

      const bidFilter = dogeToken.filters.LiquidationBid();
      const bidEvents = await dogeToken.queryFilter(
        bidFilter,
        preBlockNumber,
        postBlockNumber
      );
      assert.lengthOf(bidEvents, 1);
    });

    it("Bids when there's a lower bid", async function () {
      const config = testingConfig();
      const bot = await AuctionBot.create(collateralBuyer, config, hre.ethers);

      await dogeToken.reportOperatorUnsafeCollateral(operatorPublicKeyHash);
      const preBlockNumber = await hre.ethers.provider.getBlockNumber();

      const lowerBid = hre.ethers.BigNumber.from(bidAmount).div(2);
      await dogeToken
        .connect(competitor)
        .liquidationBid(operatorPublicKeyHash, lowerBid);

      await bot.processNextBlocks();
      const postBlockNumber = await hre.ethers.provider.getBlockNumber();

      const bidFilter = dogeToken.filters.LiquidationBid();
      const bidEvents = await dogeToken.queryFilter(
        bidFilter,
        preBlockNumber,
        postBlockNumber
      );
      assert.lengthOf(bidEvents, 2);
    });
  });

  describe("Auction closing", function () {
    it("Closes auction when winning", async function () {
      const config = testingConfig();
      const bot = await AuctionBot.create(collateralBuyer, config, hre.ethers);

      await dogeToken.reportOperatorUnsafeCollateral(operatorPublicKeyHash);
      const preBlockNumber = await hre.ethers.provider.getBlockNumber();

      await bot.processNextBlocks();

      await blockchainTimeoutSeconds(2 * 60 * 60 + 1);
      await mineBlocks(1);
      await bot.processNextBlocks();
      const postBlockNumber = await hre.ethers.provider.getBlockNumber();

      const closeFilter = dogeToken.filters.OperatorCollateralAuctioned();
      const closeEvents = await dogeToken.queryFilter(
        closeFilter,
        preBlockNumber,
        postBlockNumber
      );
      assert.lengthOf(closeEvents, 1);
    });
  });
});

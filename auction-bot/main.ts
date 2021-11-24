import type ethersT from "ethers";
// import type {} from "sequelize";

import type { Config } from "./config";
import { AuctionDb, initializeDb } from "./db";
import auctionAbi from "./auction-abi.json";

const MAXIMUM_BLOCK_INTERVAL = 16;

// TODO: use db transactions
export class AuctionBot {
  private stopped = false;

  private constructor(
    public readonly config: Config,
    private readonly ethers: typeof ethersT.ethers,
    public readonly ethSigner: ethersT.Signer,
    public readonly ethProvider: ethersT.providers.Provider,
    public readonly auctionContract: ethersT.Contract,
    private readonly db: AuctionDb
  ) {}

  public static async create(
    ethSigner: ethersT.Signer,
    config: Config,
    ethers: typeof ethersT.ethers
  ): Promise<AuctionBot> {
    if (ethSigner.provider === undefined) {
      throw new Error("Signer must be connected to an Ethereum network.");
    }

    const db = await initializeDb(config);
    const auctionContract = new ethers.Contract(
      config.auctionAddress,
      auctionAbi,
      ethSigner
    );

    const bot = new AuctionBot(
      config,
      ethers,
      ethSigner,
      ethSigner.provider,
      auctionContract,
      db
    );

    const indexerState = await db.IndexerStateModel.findByPk(config.indexerId);
    if (indexerState === null) {
      await bot.initialize();
    }

    return bot;
  }

  private async initialize() {
    let blockNumber: number;
    if (typeof this.config.startingBlock === "string") {
      const currentBlock = await this.ethProvider.getBlock(
        this.config.startingBlock
      );
      blockNumber = currentBlock.number;
    } else {
      blockNumber = this.config.startingBlock;
    }

    const state = await this.db.IndexerStateModel.create({
      id: this.config.indexerId,
      lastIndexedBlock: blockNumber,
    });
    await state.save();
  }

  public async getFirstUnindexedBlockNumber() {
    const state = await this.db.IndexerStateModel.findByPk(
      this.config.indexerId
    );
    if (state === null) {
      throw new Error("Database not initialized.");
    }

    return state.lastIndexedBlock + 1;
  }

  public async processNextBlocks() {
    const state = await this.db.IndexerStateModel.findByPk(
      this.config.indexerId
    );
    if (state === null) {
      throw new Error("Database not initialized.");
    }

    // TODO: we should be using the following instead but this breaks our unit tests due to
    // https://github.com/nomiclabs/hardhat/issues/1247
    // const lastBlockNumber = await this.ethProvider.getBlockNumber();
    const { number: lastBlockNumber } = await this.ethProvider.getBlock(
      "latest"
    );
    const firstBlockNumber = state.lastIndexedBlock + 1;

    const delta = Math.min(
      lastBlockNumber - firstBlockNumber,
      MAXIMUM_BLOCK_INTERVAL
    );
    if (delta < 0) return;
    const upperBoundBlock = firstBlockNumber + delta;

    const auctionEvents = await this.getEventsFromBlocks(
      firstBlockNumber,
      upperBoundBlock
    );

    const botAddress = await this.ethSigner.getAddress();
    const bidAmount = this.ethers.BigNumber.from(this.config.bidAmount);
    const newAuctionEvents = await this.processBids(
      auctionEvents,
      botAddress,
      bidAmount
    );

    await this.bidInAuctions(newAuctionEvents, bidAmount);

    await this.closeAuctions(upperBoundBlock);

    state.lastIndexedBlock = upperBoundBlock;
    await state.save();
  }

  private async getEventsFromBlocks(
    firstBlock: number,
    lastBlock: number
  ): Promise<ethersT.Event[]> {
    const auctionOpenFilter = this.auctionContract.filters.OperatorLiquidated();
    const auctionBidFilter = this.auctionContract.filters.LiquidationBid();
    // Currently unused
    // const auctionCloseFilter = this.auctionContract.filters.OperatorCollateralAuctioned();

    const openEvents = await this.auctionContract.queryFilter(
      auctionOpenFilter,
      firstBlock,
      lastBlock
    );
    const bidEvents = await this.auctionContract.queryFilter(
      auctionBidFilter,
      firstBlock,
      lastBlock
    );
    const events = openEvents.concat(bidEvents).sort((a, b) => {
      return a.blockNumber - b.blockNumber || a.logIndex - b.logIndex;
    });
    return events;
  }

  private async processBids(
    events: ethersT.Event[],
    botAddress: string,
    botBid: ethersT.BigNumber
  ): Promise<ethersT.Event[]> {
    const recentlyOpenedAuctions: Record<string, ethersT.Event> = {};

    for (const event of events) {
      const { args, event: eventName } = event;
      if (args === undefined) {
        throw new Error(`Unexpected missing arguments in auction event.
  Event: ${eventName}`);
      }

      if (eventName === "OperatorLiquidated") {
        // New auction
        recentlyOpenedAuctions[args.operatorPublicKeyHash] = event;
      } else if (eventName === "LiquidationBid") {
        if (args.bidder === botAddress) {
          // Ignore if this bid is on our behalf
          continue;
        }
        // Check if bid outbids us.
        if (botBid.lte(args.bid)) {
          if (args.operatorPublicKeyHash in recentlyOpenedAuctions) {
            delete recentlyOpenedAuctions[args.operatorPublicKeyHash];
          } else {
            await this.removeAuctionIfActive(args.operatorPublicKeyHash);
          }
        }
      }
    }

    return Object.values(recentlyOpenedAuctions);
  }

  private async removeAuctionIfActive(
    operatorPublicKeyHash: string
  ): Promise<void> {
    const auction = await this.db.ActiveAuctionModel.findByPk(
      operatorPublicKeyHash
    );
    if (auction === null) return;

    return auction.destroy();
  }

  /**
   * @param openEvents Open events of auctions that the bot will bid in.
   */
  private async bidInAuctions(
    openEvents: ethersT.Event[],
    bidAmount: ethersT.BigNumber
  ) {
    for (const open of openEvents) {
      if (open.args === undefined) {
        throw new Error("Unexpected missing arguments in open auction event.");
      }

      await this.auctionContract.liquidationBid(
        open.args.operatorPublicKeyHash,
        bidAmount
      );

      await this.db.ActiveAuctionModel.create({
        operatorPublicKeyHash: open.args.operatorPublicKeyHash,
        endTimestamp: open.args.endTimestamp,
      });
    }
  }

  private async closeAuctions(latestBlockNumber: number): Promise<void> {
    const auctions = await this.db.ActiveAuctionModel.findAll();
    const block = await this.ethProvider.getBlock(latestBlockNumber);
    const currentTimestamp = block.timestamp;
    if (typeof currentTimestamp !== "number")
      throw new Error("Unexpected type in timestamp.");
    for (const auction of auctions) {
      if (auction.endTimestamp >= currentTimestamp) continue;

      await this.auctionContract.closeLiquidationAuction(
        auction.operatorPublicKeyHash
      );

      await auction.destroy();
    }
  }
}

import type { Options } from "sequelize";
import type { providers } from "ethers";

export interface Config {
  /**
   * If the database is empty, the bot will start monitoring events at this block.
   * The starting block should be fairly recent.
   */
  startingBlock: providers.BlockTag;
  /**
   * The bot will only read blocks that are confirmed at least this number of times.
   */
  numberOfConfirmations: number;
  /**
   * Database ORM options.
   */
  sequelizeOptions: Options;
  /**
   * Amount to bid in an active auction.
   */
  bidAmount: string;
  /**
   * Auction contract address.
   */
  auctionAddress: string;
  /**
   * Identifier for the auction indexer.
   * Should always be zero.
   */
  indexerId: 0;
}

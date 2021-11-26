import type { Options } from "sequelize";
import type { providers } from "ethers";

/**
 * User-facing bot configuration.
 */
export interface UserConfig {
  /**
   * If the database is empty, the bot will start monitoring events at this block.
   * The starting block should be fairly recent.
   */
  startingBlock?: providers.BlockTag;
  /**
   * The bot will only read blocks that are confirmed at least this number of times.
   */
  numberOfConfirmations?: number;
  /**
   * Database file path.
   */
  dbPath: string;
  /**
   * Amount to bid in an active auction.
   */
  bidAmount: string;
  /**
   * Auction contract address.
   * Should be in hex string format.
   */
  auctionAddress: string;
  /**
   * Private key of the bidder.
   * Should be in hex string format.
   */
  bidderPrivateKey: string;
  /**
   * Ethereum node URL.
   */
  ethereumNodeURL: string;
}

/**
 * Internal bot configuration.
 */
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
   * Should be in hex string format.
   */
  auctionAddress: string;
  /**
   * Identifier for the auction indexer.
   * Should always be zero.
   * E.g. "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
   */
  indexerId: 0;
}

export function createConfig(partialConfig: UserConfig): Config {
  return {
    indexerId: 0,
    auctionAddress: partialConfig.auctionAddress,
    bidAmount: partialConfig.bidAmount,
    numberOfConfirmations: partialConfig.numberOfConfirmations || 10,
    startingBlock: partialConfig.startingBlock || "latest",
    sequelizeOptions: {
      dialect: "sqlite",
      storage: partialConfig.dbPath,
      logging: false,
    },
  };
}

export function isUserConfig(config: any): config is UserConfig {
  return (
    typeof config.auctionAddress === "string" &&
    typeof config.bidAmount === "string" &&
    (typeof config.numberOfConfirmations === "undefined" ||
      isSafeInteger(config.numberOfConfirmations)) &&
    (typeof config.startingBlock === "undefined" ||
      typeof config.startingBlock === "string" ||
      isSafeInteger(config.startingBlock)) &&
    typeof config.dbPath === "string" &&
    typeof config.bidderPrivateKey === "string" &&
    typeof config.ethereumNodeURL === "string"
  );
}

function isSafeInteger(someNumber: any): boolean {
  return typeof someNumber === "number" && Number.isSafeInteger(someNumber);
}

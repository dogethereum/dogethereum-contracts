import { DataTypes, Model, ModelCtor, Sequelize } from "sequelize";

import type { Config } from "./config";

export interface AuctionDb {
  ActiveAuctionModel: ModelCtor<ActiveAuction>;
  IndexerStateModel: ModelCtor<IndexerState>;
  sequelize: Sequelize;
}

interface ActiveAuction extends Model {
  operatorPublicKeyHash: string;
  endTimestamp: number;
}

interface IndexerState extends Model {
  id: number;
  lastIndexedBlock: number;
}

export async function initializeDb(config: Config): Promise<AuctionDb> {
  const sequelize = new Sequelize(config.sequelizeOptions);

  const ActiveAuctionModel = sequelize.define<ActiveAuction>("ActiveAuction", {
    operatorPublicKeyHash: {
      primaryKey: true,
      type: DataTypes.STRING,
    },
    endTimestamp: {
      type: DataTypes.INTEGER({ length: 8 }),
    },
  });

  const IndexerStateModel = sequelize.define<IndexerState>("IndexerState", {
    id: {
      primaryKey: true,
      type: DataTypes.INTEGER.UNSIGNED,
    },
    lastIndexedBlock: {
      type: DataTypes.INTEGER({ length: 8, unsigned: true }),
    },
  });

  await sequelize.sync();

  return {
    ActiveAuctionModel,
    IndexerStateModel,
    sequelize,
  };
}

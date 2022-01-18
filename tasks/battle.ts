import type { Contract, ContractTransaction, ContractReceipt, Event } from "ethers";
import type { HardhatRuntimeEnvironment } from "hardhat/types";

import { loadDeployment } from "../deploy";

export interface BridgeEvent {
  /**
   * Event name
   */
  name: string;
  /**
   * Event arguments
   */
  args: Record<string, any>;
}

export function normalizeEvent({ event, args }: Event): BridgeEvent {
  if (args === undefined || event === undefined) {
    throw new Error("Invalid event");
  }
  return {
    name: event,
    args,
  };
}

export async function getLastBattle(hre: HardhatRuntimeEnvironment): Promise<Battle> {
  const deployment = await loadDeployment(hre);
  return Battle.createFromLastBattle(deployment.battleManager.contract);
}

/**
 * This is a class that helps implementing a superblock challenger.
 */
export class Battle {
  private readonly headersQueried: Record<string, boolean> = {};
  private readonly scryptHashQueried: Record<string, boolean> = {};

  private constructor(
    public readonly battleManager: Contract,
    public readonly sessionId: string,
    public readonly superblockHash: string
  ) {}

  static async createFromLastBattle(battleManager: Contract): Promise<Battle> {
    const filter = battleManager.filters.NewBattle();
    const events = await battleManager.queryFilter(filter, 0, "latest");
    if (events.length === 0) {
      throw new Error("No battles started yet.");
    }

    const lastEvent = normalizeEvent(events[events.length - 1]);
    return Battle.createFromEvent(battleManager, lastEvent);
  }

  static async createFromEvent(battleManager: Contract, event: BridgeEvent): Promise<Battle> {
    const eventArgs = event.args;
    if (eventArgs === undefined) {
      throw new Error("Bad challenge event: no arguments");
    }

    if (battleManager.signer === undefined) {
      throw new Error("Expected battle manager contract to be connected to a signer.");
    }

    const address = await battleManager.signer.getAddress();
    if (address !== eventArgs.challenger) {
      throw new Error("Signer connected to battle manager is not the challenger.");
    }

    const battle = new Battle(battleManager, eventArgs.sessionId, eventArgs.superblockHash);
    return battle;
  }

  public async queryMerkleRootHashes(): Promise<ContractReceipt> {
    const queryTx: ContractTransaction = await this.battleManager.functions.queryMerkleRootHashes(
      this.superblockHash,
      this.sessionId
    );
    const receipt = await queryTx.wait();

    return receipt;
  }

  public getBlockHashes(): Promise<string[]> {
    return this.battleManager.callStatic.getDogeBlockHashes(this.sessionId);
  }

  public async queryBlockHeader(blockHash: string): Promise<ContractReceipt> {
    if (this.headersQueried[blockHash]) {
      throw new Error(`Block header ${blockHash} already queried!`);
    }
    const queryTx: ContractTransaction = await this.battleManager.functions.queryBlockHeader(
      this.superblockHash,
      this.sessionId,
      blockHash
    );
    const receipt = await queryTx.wait();

    this.headersQueried[blockHash] = true;
    return receipt;
  }

  public async requestScryptHashValidation(blockHash: string): Promise<ContractReceipt> {
    if (this.scryptHashQueried[blockHash]) {
      throw new Error(`Block header ${blockHash} already queried!`);
    }
    const queryTx: ContractTransaction =
      await this.battleManager.functions.requestScryptHashValidation(
        this.superblockHash,
        this.sessionId,
        blockHash
      );
    const receipt = await queryTx.wait();

    this.scryptHashQueried[blockHash] = true;
    return receipt;
  }

  public async nextResponse(firstBlock: number, timeoutMs = 120000): Promise<BridgeEvent[]> {
    const filters = [
      this.battleManager.filters.RespondMerkleRootHashes(),
      this.battleManager.filters.RespondBlockHeader(),
      this.battleManager.filters.ResolvedScryptHashValidation(),
    ];

    const startTime = Date.now();
    const events: BridgeEvent[] = [];
    while (events.length === 0) {
      if (startTime + timeoutMs <= Date.now()) {
        // TODO: have this return a result that specifies that
        // the defender can be timed out to win the battle instead.
        throw new Error("Defender timed out!");
      }
      const lastBlock = await this.battleManager.provider.getBlockNumber();
      if (lastBlock - firstBlock >= 0) {
        for (const filter of filters) {
          const rawEvents = await this.battleManager.queryFilter(filter, firstBlock, lastBlock);
          events.push(
            ...rawEvents.map(normalizeEvent).filter(({ args }) => {
              return (
                args.superblockHash === this.superblockHash && args.sessionId === this.sessionId
              );
            })
          );
        }

        firstBlock = lastBlock + 1;
      }

      await delay(200);
    }

    return events;
  }
}

function delay(milliseconds: number) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

import hre from "hardhat";
import type { Contract, ContractTransaction, ContractReceipt, Event } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { DogethereumSystem, loadDeployment } from "../deploy";

export async function getLastBattle(): Promise<Battle> {
  const deployment = await loadDeployment(hre);
  return Battle.createFromLastBattle(deployment);
}

export class Battle {
  public readonly battleManager: Contract;
  private readonly headersQueried: Record<string, boolean> = {};
  private readonly scryptHashQueried: Record<string, boolean> = {};

  private constructor(
    deployment: DogethereumSystem,
    public readonly challenger: SignerWithAddress,
    public readonly sessionId: string,
    public readonly superblockHash: string
  ) {
    this.battleManager = deployment.battleManager.contract.connect(challenger);
  }

  static async createFromLastBattle(
    deployment: DogethereumSystem
  ): Promise<Battle> {
    const battleManager = deployment.battleManager.contract;
    const filter = battleManager.filters.NewBattle();
    const events = await battleManager.queryFilter(filter, 0, "latest");
    if (events.length === 0) {
      throw new Error("No battles started yet.");
    }

    const lastEvent = events[events.length - 1];
    return Battle.createFromEvent(deployment, lastEvent);
  }

  static async createFromEvent(deployment: DogethereumSystem, event: Event): Promise<Battle> {
    const eventArgs = event.args!;
    const challenger = await hre.ethers.getSigner(eventArgs.challenger);
    const battle = new Battle(
      deployment,
      challenger,
      eventArgs.sessionId,
      eventArgs.superblockHash
    );
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
    const queryTx: ContractTransaction = await this.battleManager.functions.requestScryptHashValidation(
      this.superblockHash,
      this.sessionId,
      blockHash
    );
    const receipt = await queryTx.wait();

    this.scryptHashQueried[blockHash] = true;
    return receipt;
  }
}

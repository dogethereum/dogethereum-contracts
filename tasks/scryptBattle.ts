import hre from "hardhat";
import type { Contract, ContractTransaction, ContractReceipt, Event } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { DogethereumSystem, loadDeployment } from "../deploy";

export async function challengeLastScryptClaim(
  challenger: SignerWithAddress
): Promise<ScryptBattle> {
  const deployment = await loadDeployment(hre);
  const tx: ContractTransaction = await deployment.scryptChecker.contract
    .connect(challenger)
    .functions.makeDeposit({
      value: hre.ethers.BigNumber.from(10).pow(17),
    });
  await tx.wait();
  return ScryptBattle.challengeLastScryptClaim(deployment, challenger);
}

export class ScryptBattle {
  private constructor(
    public readonly scryptVerifier: Contract,
    public readonly challenger: SignerWithAddress,
    public readonly claimId: string,
    public readonly sessionId: string
  ) {
    this.scryptVerifier = scryptVerifier.connect(challenger);
  }

  static async challengeLastScryptClaim(
    deployment: DogethereumSystem,
    challenger: SignerWithAddress
  ): Promise<ScryptBattle> {
    const scryptClaims = deployment.scryptChecker.contract;
    const filter = scryptClaims.filters.ClaimCreated();
    const events = await scryptClaims.queryFilter(filter, 0, "latest");
    if (events.length === 0) {
      throw new Error("No claims made yet.");
    }

    const lastEvent = events[events.length - 1];
    return ScryptBattle.challengeClaimCreatedEvent(deployment, lastEvent, challenger);
  }

  static async challengeClaimCreatedEvent(
    deployment: DogethereumSystem,
    event: Event,
    challenger: SignerWithAddress
  ): Promise<ScryptBattle> {
    const eventArgs = event.args!;
    const claimId = eventArgs.claimId;
    const scryptClaims = deployment.scryptChecker.contract.connect(challenger);
    let tx: ContractTransaction = await scryptClaims.functions.challengeClaim(claimId);
    let receipt = await tx.wait();

    tx = await scryptClaims.functions.runNextVerificationGame(claimId);
    receipt = await tx.wait();
    const gameStartedEvents = receipt.events!.filter((event) => {
      return event.event === "VerificationGameStarted";
    });

    if (gameStartedEvents.length === 0) {
      throw new Error("No verification games found!");
    }

    const gameStartedEvent = gameStartedEvents[0];
    const sessionId = gameStartedEvent.args!.sessionId;

    const scryptVerifierAddress = await scryptClaims.callStatic.scryptVerifier();
    const scryptVerifier = await hre.ethers.getContractAt("ScryptVerifier", scryptVerifierAddress);

    const battle = new ScryptBattle(scryptVerifier, challenger, claimId, sessionId);
    return battle;
  }

  public async query(step: number): Promise<ContractReceipt> {
    const queryTx: ContractTransaction = await this.scryptVerifier.functions.query(
      this.sessionId,
      step
    );
    const receipt = await queryTx.wait();

    return receipt;
  }
}

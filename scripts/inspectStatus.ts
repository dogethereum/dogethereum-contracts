import type { Contract, Event, utils } from "ethers";
import type { HardhatRuntimeEnvironment } from "hardhat/types";
import type { DogethereumSystem } from "../deploy";

import { getWalletFor, Role } from "./signers";

export async function printStatus(
  hre: HardhatRuntimeEnvironment,
  deployment: DogethereumSystem
): Promise<void> {
  const superblocks = deployment.superblocks.contract;
  const superblockClaims = deployment.superblockClaims.contract;
  console.log("Superblocks");
  console.log("---------");
  const bestSuperblockHash = await superblocks.callStatic.getBestSuperblock();
  console.log(`Best superblock hash: ${bestSuperblockHash.toString(16)}`);
  const bestSuperblockHeight = await superblocks.callStatic.getSuperblockHeight(
    bestSuperblockHash
  );
  console.log(`Best superblock height: ${bestSuperblockHeight}`);
  const lastHash = await superblocks.callStatic.getSuperblockLastHash(
    bestSuperblockHash
  );
  console.log(`lastHash: ${lastHash}`);
  const indexNextSuperblock = await superblocks.callStatic.getIndexNextSuperblock();
  console.log(`indexNextSuperblock: ${indexNextSuperblock}`);
  const newSuperblockEventTimestamp = await superblockClaims.callStatic.getNewSuperblockEventTimestamp(
    bestSuperblockHash
  );
  console.log(`newSuperblockEventTimestamp: ${newSuperblockEventTimestamp}`);
  // idea: merge these into a single list and sort them by tx execution order?
  const superblockClaimEvents = [
    "SuperblockClaimCreated",
    "SuperblockClaimChallenged",
    "VerificationGameStarted",
    "SuperblockBattleDecided",
    "SuperblockClaimPending",
    "SuperblockClaimSuccessful",
    "SuperblockClaimFailed",
    "ErrorClaim",
  ];
  await printSuperblockClaimEvents(superblockClaimEvents, superblockClaims);
  console.log("");

  console.log("DogeToken");
  console.log("---------");
  const dogeToken = deployment.dogeToken.contract;

  await showBalance(dogeToken, "0x92ecc1ba4ea10f681dcf35c02f583e59d2b99b4b");

  const userWallet = getWalletFor(Role.User);
  await showBalance(dogeToken, userWallet.address);

  await showBalance(dogeToken, "0xf5fa014271b7971cb0ae960d445db3cb3802dfd9");

  const dogeEthPrice = await dogeToken.callStatic.dogeEthPrice();
  console.log(`Doge-Eth price: ${dogeEthPrice}`);

  // Operators
  const operatorsLength = await dogeToken.getOperatorsLength();
  console.log(`operators length: ${operatorsLength}`);
  for (let i = 0; i < operatorsLength; i++) {
    const {
      key: operatorPublicKeyHash,
      deleted,
    }: { key: string; deleted: boolean } = await dogeToken.operatorKeys(i);
    if (!deleted) {
      // not deleted
      const {
        ethAddress,
        dogeAvailableBalance,
        dogePendingBalance,
        nextUnspentUtxoIndex,
        ethBalance,
      } = await dogeToken.operators(operatorPublicKeyHash);
      console.log(
        `operator [${operatorPublicKeyHash}]:
  eth address: ${ethAddress},
  dogeAvailableBalance: ${dogeAvailableBalance},
  dogePendingBalance: ${dogePendingBalance},
  nextUnspentUtxoIndex: ${nextUnspentUtxoIndex},
  ethBalance: ${hre.web3.utils.fromWei(ethBalance.toString())}`
      );
      const utxosLength = await dogeToken.getUtxosLength(operatorPublicKeyHash);
      console.log(`utxosLength: ${utxosLength}`);
      for (let j = 0; j < utxosLength; j++) {
        const { value, txHash, index } = await dogeToken.getUtxo(
          operatorPublicKeyHash,
          j
        );
        console.log(`utxo [${j}]: ${txHash.toHexString()}, ${index}, ${value}`);
      }
    }
  }

  // Current block number
  const ethBlockNumber = await hre.ethers.provider.getBlockNumber();
  console.log(`Eth Current block: ${ethBlockNumber}`);

  // Unlock events
  const unlockRequestFilter = dogeToken.filters.UnlockRequest();
  const unlockRequestEvents = await dogeToken.queryFilter(
    unlockRequestFilter,
    0,
    "latest"
  );
  await printUnlockEvent(unlockRequestEvents, dogeToken);

  // Lock events
  const dogeTokenLockFilter = dogeToken.filters.NewToken();
  const dogeTokenLockEvents = await dogeToken.queryFilter(
    dogeTokenLockFilter,
    0,
    "latest"
  );
  await printLockEvent(dogeTokenLockEvents, dogeToken);

  // Error events
  const dogeTokenErrorFilter = dogeToken.filters.ErrorDogeToken();
  const dogeTokenErrorEvents = await dogeToken.queryFilter(
    dogeTokenErrorFilter,
    0,
    "latest"
  );
  console.log("dogeTokenErrorEvents");
  console.log(dogeTokenErrorEvents);
}

async function printUnlockEvent(events: Event[], dogeToken: Contract) {
  if (events.length === 0) {
    console.log("No unlock events.");
    return;
  }

  console.log("Unlock events");

  for (const event of events) {
    const fragment = dogeToken.interface.getEvent(event.eventSignature!);
    const args = enumerateEventArguments(event, fragment);
    const {
      from,
      dogeAddress,
      value,
      operatorFee,
      timestamp,
      selectedUtxos,
      dogeTxFee,
      operatorPublicKeyHash,
    } = await dogeToken.getUnlockPendingInvestorProof(event.args!.id, {
      blockTag: event.blockNumber,
    });
    console.log(`- tx hash: ${event.transactionHash} log index: ${event.logIndex}
  block number: ${event.blockNumber}
  args: ${args}
  from: ${from}
  dogecoin address: ${dogeAddress}
  value: ${value}
  operator fee: ${operatorFee}
  timestamp: ${timestamp}
  selectedUtxos: ${selectedUtxos}
  doge tx fee: ${dogeTxFee}
  operator public key hash: ${operatorPublicKeyHash}`);
  }
}

async function printLockEvent(events: Event[], dogeToken: Contract) {
  if (events.length === 0) {
    console.log("No lock events.");
    return;
  }

  console.log("Lock events");

  for (const event of events) {
    const fragment = dogeToken.interface.getEvent(event.eventSignature!);
    const args = enumerateEventArguments(event, fragment);
    console.log(`- tx hash: ${event.transactionHash} log index: ${event.logIndex}
  block number: ${event.blockNumber}
  args: ${args}`);
  }
}

async function showBalance(dogeToken: Contract, address: string) {
  const balance = await dogeToken.callStatic.balanceOf(address);
  console.log(`DogeToken Balance of ${address}: ${balance}`);
}

async function printSuperblockClaimEvents(
  eventNames: string[],
  superblockClaims: Contract
) {
  console.log(`SuperblockClaims events`);
  for (const eventName of eventNames) {
    const filter = superblockClaims.filters[eventName]();
    const events = await superblockClaims.queryFilter(filter, 0, "latest");

    console.log(`- ${eventName}`);
    for (const event of events) {
      const fragment = superblockClaims.interface.getEvent(
        event.eventSignature!
      );
      const args = enumerateEventArguments(event, fragment);
      console.log(`  - tx hash: ${event.transactionHash} log index: ${event.logIndex}
    block number: ${event.blockNumber}
    args: ${args}`);
    }
  }
}

function enumerateEventArguments(
  event: Event,
  fragment: utils.EventFragment
): string {
  if (event.args === undefined) {
    throw new Error("Arguments missing in ${event.event} event.");
  }

  let args = "";
  // Event argument names are present in the `event.args` as custom properties,
  // but they are hard to enumerate. This is why we use the event fragment instead.
  for (const [index, value] of event.args.entries()) {
    args += `${fragment.inputs[index].name}: ${value}  `;
  }
  return args;
}

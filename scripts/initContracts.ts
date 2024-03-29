import type { HardhatRuntimeEnvironment } from "hardhat/types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import type { DogethereumSystem, SuperblockHeader } from "../deploy";
import type ethers from "ethers";

import { operatorSignItsEthAddress } from "./../test/utils";

// TODO: choose better names for these
export const localSuperblockGenesis: SuperblockHeader = {
  merkleRoot:
    "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5",
  accumulatedWork: "0",
  timestamp: 1296688602,
  prevTimestamp: 0,
  lastHash:
    "0x3d2160a3b5dc4a9d62e7e66a295f70313ac808440ef7400d6c0772171ce973a5",
  lastBits: 0x207fffff,
  parentId:
    "0x0000000000000000000000000000000000000000000000000000000000000000",
};
export const integrationSuperblockGenesis: SuperblockHeader = {
  merkleRoot:
    "0x629417921bc4ab79db4a4a02b4d7946a4d0dbc6a3c5bca898dd12eacaeb8b353",
  accumulatedWork: "4266257060811936889868",
  timestamp: 1535743139,
  prevTimestamp: 1535743100,
  lastHash:
    "0xe2a056368784e63b9b5f9c17b613718ef7388a799e8535ab59be397019eff798",
  lastBits: 436759445,
  parentId:
    "0x0000000000000000000000000000000000000000000000000000000000000000",
};

export async function initContracts(
  hre: HardhatRuntimeEnvironment,
  deployment: DogethereumSystem,
  superblockGenesis: SuperblockHeader
): Promise<void> {
  const [, , , operatorSigner] = await hre.ethers.getSigners();
  const dogeToken = deployment.dogeToken.contract.connect(operatorSigner);
  await initDogeToken(dogeToken);
  const superblocks = deployment.superblocks.contract;
  await initSuperblocks(superblocks, superblockGenesis);
}

async function initDogeToken(dogeToken: ethers.Contract) {
  if (!(dogeToken.signer instanceof SignerWithAddress)) {
    throw new Error(
      "Expected a SignerWithAddress in the DogeToken contract instance"
    );
  }
  const operatorSigner = dogeToken.signer as SignerWithAddress;

  // Calculate operator public key
  const operatorPublicKeyHash = "0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6";
  const operatorPrivateKeyString =
    "105bd30419904ef409e9583da955037097f22b6b23c57549fe38ab8ffa9deaa3";

  const [
    operatorPublicKeyCompressedString,
    signature,
  ] = operatorSignItsEthAddress(
    operatorPrivateKeyString,
    operatorSigner.address
  );

  let tx: ethers.ContractTransaction = await dogeToken.addOperator(
    operatorPublicKeyCompressedString,
    signature
  );
  await verifyDogeTokenErrorEvents(tx);

  tx = await dogeToken.addOperatorDeposit(operatorPublicKeyHash, {
    value: "1000000000000000000",
  });
  await verifyDogeTokenErrorEvents(tx);
}

async function verifyDogeTokenErrorEvents(tx: ethers.ContractTransaction) {
  const { events } = await tx.wait();
  if (events === undefined || events === null) {
    return;
  }

  const errorEvents = events.filter((event) => {
    return event.event === "DogeTokenError";
  });

  if (errorEvents.length > 0) {
    throw new Error(`An error occurred in a transaction sent to the dogethereum token contract.
${errorEvents}`);
  }
}

async function initSuperblocks(
  superblocks: ethers.Contract,
  superblockGenesis: SuperblockHeader
) {
  return superblocks.initialize(
    superblockGenesis.merkleRoot,
    superblockGenesis.accumulatedWork,
    superblockGenesis.timestamp,
    superblockGenesis.prevTimestamp,
    superblockGenesis.lastHash,
    superblockGenesis.lastBits,
    superblockGenesis.parentId
  );
}

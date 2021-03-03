import hre from "hardhat";
import { loadDeployment } from "../deploy";

async function main() {
  const {
    dogeToken: { contract: dogeToken },
  } = await loadDeployment(hre);
  while (true) {
    // TODO: parametrize public key?
    const operatorPublicKeyHash = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
    const utxosLength = await dogeToken.getUtxosLength(operatorPublicKeyHash);
    console.log(`Utxo length of operator ${operatorPublicKeyHash} : ${utxosLength}`);
    if (utxosLength > 1) {
      return;
    }
  }
}

function delay(milliseconds: number) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

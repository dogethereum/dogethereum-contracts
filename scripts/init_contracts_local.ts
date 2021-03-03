import hre from "hardhat";
import { contractsLocalSuperblockInit, initSuperblocks } from "./initContracts";
import { loadDeployment } from "../deploy";

async function initContractsLocal() {
  console.log("init_contracts_local begin");

  const {
    superblocks: { contract: superblocks },
  } = await loadDeployment(hre);
  await initSuperblocks(superblocks, contractsLocalSuperblockInit);

  console.log("init_contracts_local end");
}

initContractsLocal()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

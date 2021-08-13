import hre from "hardhat";
import { localSuperblockGenesis, initContracts } from "./initContracts";
import { loadDeployment } from "../deploy";

async function initContractsLocal() {
  console.log("init_contracts_local begin");

  const deployment = await loadDeployment(hre);
  await initContracts(hre, deployment, localSuperblockGenesis);

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

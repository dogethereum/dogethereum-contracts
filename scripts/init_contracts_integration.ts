import hre from "hardhat";
import {
  contractsIntegrationSuperblockInit,
  initContracts,
} from "./initContracts";
import { loadDeployment } from "../deploy";

async function initContractsIntegration() {
  console.log("init_contracts_integration begin");

  const deployment = await loadDeployment(hre);
  await initContracts(hre, deployment, contractsIntegrationSuperblockInit);

  console.log("init_contracts_integration end");
}

initContractsIntegration()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

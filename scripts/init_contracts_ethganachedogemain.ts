import hre from "hardhat";
import { contractsLocalSuperblockInit, initContracts } from "./initContracts";
import { loadDeployment } from "../deploy";

async function initContractsLocal() {
  console.log("init_contracts_ethganachedogemain begin");

  const deployment: any = await loadDeployment(hre);
  await initContracts(hre, deployment, contractsLocalSuperblockInit);

  console.log("init_contracts_ethganachedogemain end");
}

initContractsLocal()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

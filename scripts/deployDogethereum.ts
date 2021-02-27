import hre from "hardhat";
import { deployDogethereum } from "../deploy";
import fs from "fs-extra";
import path from "path";

async function main() {
  const deploymentDir = path.join(hre.config.paths.root, "deployment", hre.network.name);
  const deploymentExists = await fs.pathExists(deploymentDir);

  if (deploymentExists) {
    // We support only one deployment for each network for now.
    throw new Error(`A deployment for ${hre.network.name} already exists.`);
  }

  const {
    superblocks,
    dogeMessageLibrary,
    dogeToken,
    scryptChecker,
    claimManager,
    battleManager,
    setLibrary,
  } = await deployDogethereum(hre);

  const contracts = [
    superblocks,
    dogeMessageLibrary,
    dogeToken,
    scryptChecker,
    claimManager,
    battleManager,
    setLibrary,
  ];

  const deploymentInfo: any = {};
  for (const contract of contracts) {
    const artifact = await hre.artifacts.readArtifact(contract.name);
    const descriptor = {
      abi: artifact.abi,
      contractName: artifact.contractName,
      sourceName: artifact.sourceName,
      address: contract.contract.address,
    }
    deploymentInfo[contract.name] = descriptor;
  }
  // TODO: store debugging symbols such as storage layout, contract types, source mappings, etc too.

  await fs.ensureDir(deploymentDir);

  const deploymentJsonPath = path.join(deploymentDir, "deployment.json");
  await fs.writeJson(deploymentJsonPath, deploymentInfo);

  const abiDir = path.join(deploymentDir, "abi");
  await fs.ensureDir(abiDir);

  // Here we output ABI files to generate wrapper classes in web3j.
  // Note that we don't support repeated contract names here.
  for (const contract of [superblocks, dogeToken, claimManager, battleManager]) {
    const info = deploymentInfo[contract.name];
    const abiJsonPath = path.join(abiDir, `${info.contractName}.json`);
    const abi = info.abi;
    await fs.writeJson(abiJsonPath, abi);
  }
}

main().then(() => {
  process.exit(0);
}).catch((error) => {
  console.error(error);
  process.exit(1);
});

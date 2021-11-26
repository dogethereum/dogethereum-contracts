import { ethers } from "ethers";
import yargs from "yargs";
import fs from "fs/promises";

import { createConfig, isUserConfig } from "./config";
import { AuctionBot } from "./main";

const pollingPeriod = 3000;

async function main() {
  const args = await yargs
    .alias("c", "config")
    .string("config")
    .demandOption("config")
    .parse();
  const json = await fs.readFile(args.config, {
    encoding: "utf8",
  });
  const userConfig = JSON.parse(json);
  if (!isUserConfig(userConfig)) {
    // TODO: specify which are missing
    throw new Error("Missing or wrong fields in configuration.");
  }
  const provider = ethers.getDefaultProvider(userConfig.ethereumNodeURL);
  const signer = new ethers.Wallet(userConfig.bidderPrivateKey, provider);
  const config = createConfig(userConfig);
  if (!ethers.utils.isAddress(config.auctionAddress)) {
    throw new Error(
      "Provided auction address is not a valid Ethereum address."
    );
  }
  const bot = await AuctionBot.create(signer, config, ethers);

  const state = { stop: false };
  const stopper = () => {
    state.stop = true;
  };
  process.on("SIGINT", stopper);
  process.on("SIGTERM", stopper);
  while (!state.stop) {
    await bot.processNextBlocks();

    await delay(pollingPeriod);
  }
}

function delay(milliseconds: number) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

main()
  .then(() => {
    console.log("Finished");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error.stack || error);
    process.exit(1);
  });

import { task, types } from "hardhat/config";
import { ActionType } from "hardhat/types";
import { promisify } from "util";

import { delay, generateTaskName, testProcess } from "./common";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const RpcClient = require("bitcoind-rpc");

export interface MineBlockTaskArguments {
  url: string;
  blocks: number;
  agentPid?: number;
}

export const MINE_BLOCK_ON_TX_TASK = generateTaskName("mineOnTx");

const mineBlockCommand: ActionType<MineBlockTaskArguments> = async function ({
  url,
  blocks,
  agentPid,
}) {
  const client = new RpcClient(url);
  const getRawMemPool = promisify(client.getRawMemPool).bind(client);
  const generate = promisify(client.generate).bind(client);

  let mempool;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    mempool = await getRawMemPool(false);
    if (mempool.error !== null) {
      throw new Error(`JSON-RPC failure: ${JSON.stringify(mempool.error)}`);
    }
    if (mempool.result.length > 0) break;
    if (agentPid !== undefined && !testProcess(agentPid)) {
      throw new Error("Agent process terminated before sending transaction to dogecoin node.");
    }
    await delay(300);
  }

  // Mine blocks
  const hashes = await generate(blocks);
  if (hashes.error !== null) throw new Error(`JSON-RPC failure: ${JSON.stringify(hashes.error)}`);
  console.log(`Mined ${hashes.result.length} blocks.`);
};

task(MINE_BLOCK_ON_TX_TASK, "Mines a dogecoin block when a transaction is detected in the mempool.")
  .addParam("url", "The URL of the dogecoin JSON-RPC endpoint.", undefined, types.string)
  .addOptionalParam("blocks", `The amount of blocks mined.`, 10, types.int)
  .addOptionalParam(
    "agentPid",
    `The agent PID. When given, the task will monitor the process to see if it's still alive while waiting for the new transaction.
If no new transaction is sent by the time the agent is closed, the task fails with an exception.`,
    undefined,
    types.int
  )
  .setAction(mineBlockCommand);

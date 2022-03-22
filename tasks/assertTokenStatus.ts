import { assert } from "chai";
import type { BigNumber } from "ethers";
import { task, types } from "hardhat/config";
import { ActionType } from "hardhat/types";
import { promisify } from "util";

import { generateTaskName, remove0x } from "./common";
import { loadDeployment } from "../deploy";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const RpcClient = require("bitcoind-rpc");

// Based on bitcoin rpc response for txs
interface Tx {
  txid: string;
  signedTx: {
    outs: Array<{
      script: {
        data: number[];
      };
    }>;
  };
}

export interface AssertLockTaskArguments {
  url: string;
  txList: Tx[];
  lockValue: number;
}

export const ASSERT_LOCK = generateTaskName("assertLock");

const assertLockCommand: ActionType<AssertLockTaskArguments> = async function (
  { lockValue, url, txList },
  hre
) {
  const client = new RpcClient(url);
  const getTransaction = promisify(client.getTransaction).bind(client);

  const txHashes = txList.map((tx) => tx.txid);

  for (const txHash of txHashes) {
    const confirmedTx = await getTransaction(txHash);
    if (confirmedTx.error !== null) {
      throw new Error(`JSON-RPC failure: ${JSON.stringify(confirmedTx.error)}`);
    }

    assert.isAbove(
      confirmedTx.result.confirmations,
      9,
      `Lock tx ${txHash} doesn't have enough confirmations.`
    );
  }

  // TODO: read actual sent value to have a more flexible assert.

  const deployment = await loadDeployment(hre);
  const dogeToken = deployment.dogeToken.contract;
  const superblocks = deployment.superblocks.contract;

  const relayTxFilter = superblocks.filters.RelayTransaction();
  const relayTxEvents = (await superblocks.queryFilter(relayTxFilter, 0, "latest")).filter((e) =>
    txHashes.includes(remove0x(e.args?.txHash))
  );
  const relayedTxHashes = relayTxEvents.map((e) => remove0x(e.args!.txHash));
  assert.sameMembers(relayedTxHashes, txHashes, "Some transactions were not relayed.");

  const userAddress = hre.ethers.utils.hexlify(txList[0].signedTx.outs[1].script.data.slice(2, 22));

  const feeFraction = await dogeToken.DOGETHEREUM_FEE_FRACTION();
  const operatorFeeRatio = await dogeToken.OPERATOR_LOCK_FEE();
  const submitterFeeRatio = await dogeToken.SUPERBLOCK_SUBMITTER_LOCK_FEE();
  const expectedUserAmount = hre.ethers.BigNumber.from(lockValue)
    .mul(feeFraction.sub(operatorFeeRatio).sub(submitterFeeRatio))
    .div(feeFraction);
  const actualUserAmount: BigNumber = await dogeToken.balanceOf(userAddress);
  assert.isTrue(
    actualUserAmount.eq(expectedUserAmount),
    "Unexpected amount of tokens given to user after lock."
  );
};

task(ASSERT_LOCK, "Mines a dogecoin block when a transaction is detected in the mempool.")
  // TODO: add example url
  .addParam("url", "The URL of the dogecoin JSON-RPC endpoint.", undefined, types.string)
  .addParam("lockValue", `The amount to be locked.`, undefined, types.int)
  .addParam("txList", `The lock tx list.`, undefined, types.json)
  .setAction(assertLockCommand);

import type { Contract } from "ethers";
import type { HardhatRuntimeEnvironment } from "hardhat/types";

export function remove0x(str: string): string {
  return str.startsWith("0x") ? str.substring(2) : str;
}

export function generateTaskName(name: string): string {
  return `dogethereum.${name}`;
}

/**
 * @return true if process is running, false if the process is terminated.
 */
export function testProcess(pid: number): boolean {
  // Signal `0` is interpreted by node.js as a test for process existence
  // See https://nodejs.org/docs/latest-v14.x/api/process.html#process_process_kill_pid_signal
  try {
    process.kill(pid, 0);
  } catch {
    return false;
  }
  return true;
}

export function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

/**
 * @param superblockTimeout Time delay until confirmation of superblock is possible.
 * @param blockNumber Last known block number.
 */
export async function accelerateTimeOnNewProposal(
  hre: HardhatRuntimeEnvironment,
  superblocks: Contract,
  superblockTimeout: number,
  blockNumber: number
): Promise<number> {
  const currentBlock = await hre.ethers.provider.getBlock("latest");
  if (blockNumber < currentBlock.number) {
    // Check superblock proposal event
    const filter = superblocks.filters.NewSuperblock();
    const newSuperblockEvents = await superblocks.queryFilter(
      filter,
      blockNumber + 1,
      currentBlock.number
    );

    if (newSuperblockEvents.length > 0) {
      const event = newSuperblockEvents[newSuperblockEvents.length - 1];
      const block = await event.getBlock();
      const timeDelta = currentBlock.timestamp - block.timestamp + superblockTimeout + 1;
      if (timeDelta > 0) {
        // Accelerate confirmation of superblocks.
        await hre.network.provider.request({
          method: "evm_increaseTime",
          params: [timeDelta],
        });
        await hre.network.provider.request({
          method: "evm_mine",
          params: [],
        });
      }
    }
  }

  return currentBlock.number;
}


export function generateTaskName(name: string): string {
  return `dogethereum.${name}`
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
import hre from "hardhat";
import type { Wallet } from "ethers";

export enum Role {
  /**
   * Token holder 1
   * This user locks dogecoin in the send-back-and-forth.sh integration test
   */
  User,
}

type KeyByRoleMap = {
  [role in Role]: string;
};

const keyByRole: KeyByRoleMap = {
  // Private key in doge format: cW9yAP8NRgGGN2qQ4vEQkvqhHFSNzeFPWTLBXriy5R5wf4KBWDbc
  // Ethereum address: 0xa3a744d64f5136aC38E2DE221e750f7B0A6b45Ef.
  [Role.User]:
    "0xffd02f8d16c657add9aba568c83770cd3f06cebda3ddb544daf313002ca5bd53",
};

export function getWalletFor(role: Role): Wallet {
  const privateKey = keyByRole[role];
  const wallet = new hre.ethers.Wallet(privateKey, hre.ethers.provider);
  return wallet;
}

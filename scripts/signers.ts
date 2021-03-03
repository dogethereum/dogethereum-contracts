import hre from "hardhat";
import type { Wallet } from "ethers";

export enum Role {
  /**
   * Token holder 1
   */
  User,
}

type KeyByRoleMap = {
  [role in Role]: string;
}

const keyByRole: KeyByRoleMap = {
  // Private key in doge format: co6nPnPXdJQRxAQbeeUo3SQn5PkGGrEqP6a4K1QCmAkXNsBWFZEk
  // Ethereum address: 0xd2394f3fad76167e7583a876c292c86ed10305da
  [Role.User]: "0xf968fec769bdd389e33755d6b8a704c04e3ab958f99cc6a8b2bcf467807f9634",
}

// TODO: parametrize role? e.g. getWalletFor(role: Role)
export async function getWalletFor(role: Role): Promise<Wallet> {
  const privateKey = keyByRole[role];
  const wallet = new hre.ethers.Wallet(privateKey, hre.ethers.provider);
  return wallet;
}

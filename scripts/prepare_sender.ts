import hre from "hardhat";
import { getWalletFor, Role } from "./signers";

// Prepares an eth account that holds doge tokens to send or unlock tokens:
// - It makes sure the address has some eth balance to send txs from it
async function main() {
  const wallet = await getWalletFor(Role.User);

  // Make sure user has some eth to pay for txs
  let userEthBalance = await wallet.getBalance();
  console.log(`sender eth balance: ${userEthBalance}`);
  if (userEthBalance.eq(0)) {
    console.log("no eth balance, sending some eth...");
    const [fundedSigner] = await hre.ethers.getSigners();
    await fundedSigner.sendTransaction({
      to: wallet.address,
      value: hre.ethers.BigNumber.from("1000000000000000000"),
    });
    userEthBalance = await wallet.getBalance();
    console.log(`sender eth balance: ${userEthBalance}`);
  }
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

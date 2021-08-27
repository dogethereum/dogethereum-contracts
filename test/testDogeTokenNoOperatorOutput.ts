import hre from "hardhat";

import { deployFixture, deployToken } from "../deploy";

import {
  buildDogeTransaction,
  dogeAddressFromKeyPair,
  dogeKeyPairFromWIF,
  isolateTests,
  publicKeyHashFromKeyPair,
} from "./utils";

describe("testDogeTokenNoOperatorOutput", function () {
  const collateralRatio = 2;
  let trustedRelayerContract: string;
  let dogeUsdPriceOracle: string;
  let ethUsdPriceOracle: string;
  let operatorEthAddress: string;
  let superblockSubmitterAddress: string;

  isolateTests();

  before(async function () {
    const signers = await hre.ethers.getSigners();
    const { dogeToken } = await deployFixture(hre);
    // Tell DogeToken to trust first account as if it were the relayer contract
    trustedRelayerContract = signers[0].address;
    operatorEthAddress = signers[3].address;
    superblockSubmitterAddress = signers[4].address;
    dogeUsdPriceOracle = await dogeToken.callStatic.dogeUsdOracle();
    ethUsdPriceOracle = await dogeToken.callStatic.ethUsdOracle();
  });

  it("Accept unlock transaction without output for operator", async function() {
    const keys = [
      "QSRUX7i1WVzFW6vx3i4Qj8iPPQ1tRcuPanMun8BKf8ySc8LsUuKx",
      "QULAK58teBn1Xi4eGo4fKea5oQDPMK4vcnmnivqzgvCPagsWHiyf",
    ].map(dogeKeyPairFromWIF);
    const tx = buildDogeTransaction({
      signer: keys[0],
      inputs: [
        {
          txId:
            "edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67",
          index: 0,
        },
      ],
      outputs: [
        {
          type: "payment",
          address: dogeAddressFromKeyPair(keys[1]),
          value: 1000000,
        },
      ],
    });
    const operatorPublicKeyHash = publicKeyHashFromKeyPair(keys[0]);
    const txData = `0x${tx.toHex()}`;
    const txHash = `0x${tx.getId()}`;

    const [signer] = await hre.ethers.getSigners();

    const {
      dogeToken: { contract: dogeToken },
    } = await deployToken(
      hre,
      "DogeTokenForTests",
      signer,
      dogeUsdPriceOracle,
      ethUsdPriceOracle,
      trustedRelayerContract,
      collateralRatio
    );

    await dogeToken.addOperatorSimple(
      operatorPublicKeyHash,
      operatorEthAddress
    );

    await dogeToken.processUnlockTransaction(
      txData,
      txHash,
      operatorPublicKeyHash,
      superblockSubmitterAddress
    );
  });
});

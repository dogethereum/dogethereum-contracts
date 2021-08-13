import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-truffle5";
import type { HardhatUserConfig } from "hardhat/types";
import "@openzeppelin/hardhat-upgrades";

import "./tasks/superblock-cli";

const config: HardhatUserConfig = {
    networks: {
        hardhat: {
            // TODO: lower this a bit?
            blockGasLimit: 4000000000,
        },
        development: {
            url: "http://127.0.0.1:8545",
        },
        integrationDogeMain: {
            url: "http://127.0.0.1:8545",
        },
        integrationDogeRegtest: {
            url: "http://127.0.0.1:8545",
        },
        integrationDogeScrypt: {
            url: "http://127.0.0.1:8545",
        },
        ropsten: {
            url: "http://127.0.0.1:8545",
            chainId: 3,
        },
        rinkeby: {
            url: "http://127.0.0.1:8545",
            chainId: 4,
        },
    },
    solidity: {
        version: "0.7.6",
        settings: { optimizer: { enabled: true, runs: 200 } },
    },
};

export default config;

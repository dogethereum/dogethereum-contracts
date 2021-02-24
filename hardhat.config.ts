// import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-truffle5";
import type { HardhatUserConfig } from "hardhat/types"

const config: HardhatUserConfig = {
    networks: {
        development: {
            url: "http://127.0.0.1:8545"
        }
    },
    solidity: "0.7.6",
};

export default config;
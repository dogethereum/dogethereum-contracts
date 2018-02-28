const HDWalletProvider = require('truffle-hdwallet-provider');
const config = require('./config');

const engine = (config.wallet) ?
  new HDWalletProvider(config.wallet.seed, config.rpcpath) : undefined;

module.exports = {
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      network_id: "*", // Match any network id
      gas: 47000000000,
      gasPrice: 1
    },
    integrationDogeMain: {
      host: "localhost",
      port: 8545,
      network_id: "*", // Match any network id
      gas: 4700000,
      gasPrice: 1
    },
    integrationDogeRegtest: {
      host: "localhost",
      port: 8545,
      network_id: "*", // Match any network id
      gas: 4700000,
      gasPrice: 1
    },
    ropsten: {
      provider: engine,
      network_id: "3", // Ropsten
      gas: 1000000,
      gasPrice: "20000000000"
    }
  }
};

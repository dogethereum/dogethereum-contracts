# Dogethereum Contracts

[![Build Status](https://travis-ci.org/dogethereum/dogethereum-contracts.svg?branch=master)](https://travis-ci.org/dogethereum/dogethereum-contracts)

Ethereum contracts for the Dogecoin <-> Ethereum bridge.

If you are new to the Dogecoin <-> Ethereum bridge, please check the [docs](https://github.com/dogethereum/docs) repository first.

## Core components
* [DogeSuperblocks contract](contracts/DogeSuperblocks.sol)
  * Keeps a copy of the Dogecoin Superblockchain
  * Informs [DogeToken contract](contracts/token/DogeToken.sol) when a Dogecoin transaction locked or unlocked funds.
  * It's kind of a Doge version of [BtcRelay](https://github.com/ethereum/btcrelay) but using Superblocks instead of blocks.
* [DogeToken contract](contracts/token/DogeToken.sol)
  * An ERC20 contract where 1 token is worth 1 Dogecoin.
  * Tokens are minted when coins are locked on the Dogecoin blockchain.
  * Tokens are destroyed when coins should go back to the Dogecoin blockchain.
* [DogeClaimManager contract](contracts/DogeClaimManager.sol)
  * Manages the interactive (challenge/response) validation of Superblocks.
  * Inspired on Truebit's Scrypt interactive [ClaimManager](https://github.com/TrueBitFoundation/scrypt-interactive/blob/master/contracts/ClaimManager.sol)
* [DogeTx library](contracts/DogeParser/DogeTx.sol)
  - Library for parsing/working with Dogecoin blocks, txs and merkle trees 


## Running the Tests

* Install prerequisites
  * [nodejs](https://nodejs.org) v9.2.0 or above.
  * [truffle](http://truffleframework.com/) v4.1.3 or above.
  * [ganache-cli](https://github.com/trufflesuite/ganache-cli) v6.1.0 or above.
* Clone this repo.
* Install npm dependencies.
  * cd to the directory where the repo is cloned.
  ```
    npm install
  ```
* Run tests:
  ```
    # first start ganache-cli
    ganache-cli --gasLimit 4000000000000

    # run tests
    truffle test
  ```

## Deployment

To deploy the contracts

### Requirements

* A Rinkeby client running with rpc enabled

### Preparation

* Copy `local_config.json.example` to `local_config.json`
* Replace _seed_ and _address_ fields in the configuration
* Verify _rpcpath_ in `config.js` points to a rinkeby RPC client

### Deployment

* Run `truffle migrate --network rinkeby`

**Note**: Do not commit `local_config.json` file!

## License

MIT License<br/>
Copyright (c) 2018 Coinfabrik & Oscar Guindzberg<br/>
[License](LICENSE)

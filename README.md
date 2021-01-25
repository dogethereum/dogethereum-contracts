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
* [DogeMessageLibrary](contracts/DogeParser/DogeMessageLibrary.sol)
  - Library for parsing/working with Dogecoin blocks, txs and merkle trees 


## Running the Tests

* Install prerequisites
  * [nodejs](https://nodejs.org) v15.5.1 or above.
  * [truffle](http://truffleframework.com/) v5.1.60 or above.
  * [ganache-cli](https://github.com/trufflesuite/ganache-cli) v6.12.1 or above.
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

### Deployment

* Run `truffle migrate --network rinkeby`

## License

MIT License<br/>
Copyright (c) 2018 Coinfabrik & Oscar Guindzberg<br/>
[License](LICENSE)

## Bounty payment address

[0xbc2eadd8dbc9f08e924550c8138e5f4e6c64489e](https://etherscan.io/address/0xbc2eadd8dbc9f08e924550c8138e5f4e6c64489e#code)

# Dogethereum Contracts

[![Build Status](https://travis-ci.org/dogethereum/dogethereum-contracts.svg?branch=master)](https://travis-ci.org/dogethereum/dogethereum-contracts)

Ethereum contracts for the Dogecoin <-> Ethereum bridge.

Core components:
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


Related projects:

* [Dogethereum agents](https://github.com/dogethereum/dogethereum-agents): External agents for the Dogecoin <-> Ethereum bridge.
* [Dogethereum tools](https://github.com/dogethereum/dogethereum-tools): External agents for the Dogecoin <-> Ethereum bridge.
* [Scrypt hash verification](https://github.com/dogethereum/scrypt-interactive): Interactive (i.e. challenge/response) validation of Scrypt hashes.



## Design

### Doge to Eth

![Design](./design.png)

### Eth to Doge

![Design](./design-eth2doge.png)

## Incentives

Some operations require gas to be spent or eth deposit to be frozen. Here are the incentives for doing that.

* Submitting a Superblock: Superblock submitters will get a fee when the superblock they sent is used to relay a tx.
* Being an operator: Each time a lock/unlock tx is made, operator gets a fee.
* Sending dogecoin txs to DogeToken: Each user will send their own dogecoin lock tx to get doge tokens.
* Superblock challenge: Challengers who find invalid superblocks will get some eth after the challenge/response game finishes.

## Actors

This is the list of external actors to the system and what they can do.

* User
  * Lock (Doge -> Eth).
  * Transfer doge tokens (Eth -> Eth).
  * Unlock (Eth -> Doge).
* Operator
  * Register themselve as operator.
  * Add/Remove Eth collateral deposit.
  * Store locked doges.
  * Create, sign & broadcast doge unlock tx.
* Superblock Submitter
  * Propose superblocks.
  * Defend superblocks.
* Superblock Challenger
  * Challenge superblocks.
* Doge/Eth Price Oracle
  * Inform Doge/Eth price rate.


## Workflows
* New Superblock
  * There is a new block on the doge blockchain, then another one, then another one...
  * Once per hour Superblock Submitters create a new Superblock containing the newly created blocks and send a Superblock summary to [DogeClaimManager contract](contracts/DogeClaimManager.sol)
  * Superblock Challengers will challenge the superblock if they find it invalid. They will request the list of block hashes, the block headers, etc. Superblock Submitters should send that information which is validated onchain by the contact.
  * A Superblock Challenger might challenge one of the block's scrypt hashes. In that case [DogeClaimManager contract](contracts/DogeClaimManager.sol) uses Truebit's [Scrypt hash verification](https://github.com/dogethereum/scrypt-interactive) to check its correctness.
  * If any information provided by the Superblock Submitter is proven wrong or if it fails to answer, the Supperblock is discarded.
  * If no challenge to the Superblock was done after a contest period (or if the challenges failed) the superblock is considered to be "approved". [DogeClaimManager contract](contracts/DogeClaimManager.sol) contract notifies [DogeSuperblocks contract](contracts/DogeSuperblocks.sol) which adds the Superblock to its Superblock chain.
 

* Sending dogecoins to ethereum
  * User selects operator (any operator who has the desired ammount of eth collateral).
  * User sends a lock doge tx of N doges to the doge network using [Dogethereum tools](https://github.com/dogethereum/dogethereum-tools) `lock` tool.
  * The doge tx is included in a doge block and several doge blocks are mined on top of it.
  * Once the doge block is included in an approved superblock, the lock tx is ready to be relayed to the eth network.
  * A doge altruistic doge lock tx submitter using [Dogethereum agents](https://github.com/dogethereum/dogethereum-agents) finds the doge lock tx (In the future there will be a tool for users to relay their own txs).
  * The doge altruistic doge lock tx submitter sends an eth tx to [DogeSuperblocks contract](contracts/DogeSuperblocks.sol) containing: the doge lock tx, a partial merkle tree proving the doge lock tx was included in a doge block, the doge block header that contains the doge lock tx, another partial merkle tree proving the block was included in a superblock and the superblock id that contains the block.
  * [DogeSuperblocks contract](contracts/DogeSuperblocks.sol) checks the consistency of the supplied information and relays the doge lock tx to [DogeToken contract](contracts/token/DogeToken.sol).
  * [DogeToken contract](contracts/token/DogeToken.sol) checks the doge lock tx sends funds to the doge address of an operator.
  * [DogeToken contract](contracts/token/DogeToken.sol) mints N tokens and assigns them to the User. [DogeToken contract](contracts/token/DogeToken.sol) calculates the User eth account address in a way that is controlled by the private key that signed the doge lock tx.


* Sending dogecoins to ethereum
  * User selects operator (any operator who has the desired ammount of locked doges).
  * User sends an eth tx to the [DogeToken contract](contracts/token/DogeToken.sol) invoking the `doUnlock` function. Destination doge address, amount and operator id are supplied as parameters.
  * [DogeToken contract](contracts/token/DogeToken.sol) select which UTXOs to spend, defines the doge tx fee, change and operator fee.
  * The operator agent that is part of [Dogethereum agents](https://github.com/dogethereum/dogethereum-agents) notices the unlock request. It creates, signs & broadcasts a doge unlock tx. 
  * The user receives the unlocked doges.
  * The operator waits the doge tx to be confirmed and included in a superblock and then relays the doge unlock tx to the eth network, so change can be used by [DogeToken contract](contracts/token/DogeToken.sol) for future unlocks.

## Notes

* [DogeSuperblocks contract](contracts/DogeSuperblocks.sol) uses a checkpoint instead of starting from dogecoin blockchain genesis.
* Dogecoin lock txs don't have to specify a destination eth address. Dogetokens will be assigned to the eth address controlled by the private key that signed the dogecoin lock tx.


## Assumptions
* Incentives will guarantee that there is always at least one honest Superblock Submitter and one honest Superblock Challenger online.
* There are no huge regorgs (i.e. 100+ block) in Doge nor in Eth blockchains


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

* A ropsten client running with rpc enabled

### Preparation

* Copy `local_config.json.example` to `local_config.json`
* Replace _seed_ and _address_ fields in the configuration
* Verify _rpcpath_ in `config.js` points to a ropsten RPC client

### Deployment

* Run `truffle migrate --network ropsten`

**Note**: Do not commit `local_config.json` file!

## Team

* [Ismael Bejarano](https://github.com/ismaelbej)
* [Catalina Juarros](https://github.com/cat-j)
* [Pablo Yabo](https://github.com/pipaman)
* [Oscar Guindzberg](https://github.com/oscarguindzberg)

## License

MIT License<br/>
Copyright (c) 2018 Coinfabrik & Oscar Guindzberg<br/>
[License](LICENSE)

## Doge-Eth bounty
This is our eth address: 0x1ed3e252dcb6d540947d2d63a911f56733d55681

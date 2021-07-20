# Dogethereum Contracts

[![Build Status](https://travis-ci.org/dogethereum/dogethereum-contracts.svg?branch=master)](https://travis-ci.org/dogethereum/dogethereum-contracts)

Ethereum contracts for the Dogecoin <-> Ethereum bridge.

If you are new to the Dogecoin <-> Ethereum bridge, please check the [docs](https://github.com/dogethereum/docs) repository first.

## Core components
- [DogeSuperblocks contract](contracts/DogeSuperblocks.sol)
  - Keeps a copy of the Dogecoin Superblockchain
  - Informs [DogeToken contract](contracts/token/DogeToken.sol) when a Dogecoin transaction locked or unlocked funds.
  - It's kind of a Doge version of [BtcRelay](https://github.com/ethereum/btcrelay) but using Superblocks instead of blocks.
- [DogeToken contract](contracts/token/DogeToken.sol)
  - An ERC20 contract where 1 token is worth 1 Dogecoin.
  - Tokens are minted when coins are locked on the Dogecoin blockchain.
  - Tokens are destroyed when coins should go back to the Dogecoin blockchain.
- [DogeClaimManager contract](contracts/DogeClaimManager.sol)
  - Manages the interactive (challenge/response) validation of Superblocks.
  - Inspired on Truebit's Scrypt interactive [ScryptClaims](https://github.com/TrueBitFoundation/scrypt-interactive/blob/master/contracts/ScryptClaims.sol)
- [DogeMessageLibrary](contracts/DogeParser/DogeMessageLibrary.sol)
  - Library for parsing/working with Dogecoin blocks, txs and merkle trees

## Prerequisites

To build, deploy or run tests on these contracts you need to install the following:
- [nodejs](https://nodejs.org) [latest LTS](https://nodejs.org/en/about/releases/) or above. This is currently fermium (v14).
- [dogecoin-qt](https://github.com/dogecoin/dogecoin)

## Installing

To run tests or deployment you need to install the root package dependencies. To do so:

- `cd` to the directory where the repo is cloned.
- Execute `npm install`.

## Running the Tests

There are two kinds of tests:

- [Contract tests](#contract-tests)
- [Integration tests](#integration-tests)

Some contracts are copies from the [scrypt-interactive](https://github.com/bridge2100/scrypt-interactive) repository. These can be found in `contracts/scrypt-interactive`. You may need to update them to test with the latest version.

### Contract tests

These are unit tests for all contract funcionality.

Just run `npm test` to run all contract tests.

### Integration tests

These tests setup an environment where the contracts are deployed and interacted with by the [dogethereum tools] and the [dogethereum agents].

First, you need to set a few environment variables:
- `agentRootDir`: path to the root of the [dogethereum agents] repository.
- `agentDataDir`: path to the data directory of the [dogethereum agents]. This is where the agents store a database of the dogecoin and ethereum networks. Specifically, this is the `data.directory` key in the agent configuration.
- `toolsRootDir`: path to the root of the [dogethereum tools] repository.

To set them, run
```shell
$ export agentRootDir=/your/agent/path
$ export agentDataDir=/your/agent/path/to/data/dir
$ export agentDataDir=/your/tools/path
```

Then run `npm run integration-tests`. Note that doing this will launch a dogecoin node in regtest mode with a graphical interface.

At one point, the test will require the manual launch of the [dogethereum agents].

### Manual testing

Additionally, there are a few dogethereum commands that facilitate performing specific operations with the contracts.
These are implemented as Hardhat tasks so you can enumerate them with `npx hardhat --help`.
To see further options you can invoke the help for that particular task. E.g. for the `dogethereum.challenge` task you can invoke `npx hardhat dogethereum.challenge --help`.

```shell
$ npx hardhat --network NETWORK COMMAND [OPTIONS]
```
Where COMMAND

- `dogethereum.challenge`: Start a challenge to a superblock

  Available OPTIONS are:

  - `--from ADDRESS`: Address used to send the challenge from.
    When not specified it will use the first account available in the runtime environment.

  - `--superblock SUPERBLOCK_ID`: Superblock ID to challenge.
    When none is specified it will challenge the next superblock.
    If the superblock was not submitted it will wait for it.

  - `--deposit AMOUNT`: It will deposit the amount of ether in the contract.
    If the balance is zero and no deposit is specified it
    will try to deposit 1000 wei.

## Deployment

To deploy the contracts there's a [basic script](scripts/deployDogethereum.ts) that takes care of writing out the deployment data into a json file.

These json files are stored into the `deployment/$NETWORK` directory, where `$NETWORK` is the hardhat network selected with the `--network` option.

Currently, all networks configured in [hardhat.config.ts](hardhat.config.ts) point to the port 8545 in the localhost. You can edit the URLs to point to third party ethereum node backend endpoints like Infura or Alchemy if you want.

To run the deployment on, e.g. rinkeby, execute:
```shell
$ npx hardhat --network rinkeby run scripts/deployDogethereum.ts
```

## License

MIT License<br/>
Copyright (c) 2018 Coinfabrik & Oscar Guindzberg<br/>
[License](LICENSE)

## Bounty payment address

[0xbc2eadd8dbc9f08e924550c8138e5f4e6c64489e](https://etherscan.io/address/0xbc2eadd8dbc9f08e924550c8138e5f4e6c64489e#code)


[dogethereum tools]: https://github.com/bridge2100/dogethereum-tools
[dogethereum agents]: https://github.com/bridge2100/dogethereum-agents
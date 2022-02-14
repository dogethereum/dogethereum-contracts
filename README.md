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
- [SuperblockClaims contract](contracts/SuperblockClaims.sol)
  - Manages the interactive (challenge/response) validation of Superblocks.
  - Inspired on Truebit's Scrypt interactive [ScryptClaims](https://github.com/TrueBitFoundation/scrypt-interactive/blob/master/contracts/ScryptClaims.sol)
- [DogeMessageLibrary](contracts/DogeParser/DogeMessageLibrary.sol)
  - Library for parsing/working with Dogecoin blocks, txs and merkle trees

## Prerequisites

To build, deploy or run tests on these contracts you need to install the following:
- bash 5.1 or above. macOS users probably have an [older version](https://www.shell-tips.com/mac/upgrade-bash/).
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

Some contracts are copies from the [scrypt-interactive] repository. These can be found in `contracts/scrypt-interactive`. You may need to update them to test with the latest version.

### Contract tests

These are unit tests for all contract funcionality.

Just run `npm test` to run all contract tests.

### Integration tests

These tests setup an environment where the contracts are deployed and interacted with by the [dogethereum tools] and the [dogethereum agents].

First, you need to set a few environment variables:
- `agentRootDir`: path to the root of the [dogethereum agents] repository.
- `agentDataDir`: path to the data directory of the [dogethereum agents]. This is where the agents store a database of the dogecoin and ethereum networks. Specifically, this is the `data.directory` key in the agent configuration.
- `agentConfig`: path to the agents config file.
- `toolsRootDir`: path to the root of the [dogethereum tools] repository.
- `scryptInteractiveDir`: path to the root of the [scrypt-interactive] repository.

To set them, run
```shell
$ export agentRootDir=/your/agent/path
$ export agentDataDir=/your/agent/path/to/data/dir
$ export agentConfig=/your/agent/config/path/dogethereum-agents.conf
$ export toolsRootDir=/your/tools/path
$ export scryptInteractiveDir=/your/path/to/scrypt-interactive
```

Then run `npm run integration-tests`. Note that doing this will launch a dogecoin node in regtest mode with a graphical interface.

The integration tests will use [ganache-cli] by default but [hardhat network] can be used instead by setting:

```shell
$ USE_HH_NETWORK=true
```

At one point, the test will require the manual launch of the [dogethereum agents].

#### Scrypt checker integration

Tests involving the scrypt checker monitor require an additional environment variable:

- `scryptInteractiveDir`: path to the root of the [scrypt-interactive] repository.

```shell
$ export scryptInteractiveDir=/your/scrypt-interactive/path
```

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

### Upgrades

The contracts support upgrades using [OpenZeppelin's upgrades plugin](https://docs.openzeppelin.com/upgrades-plugins/1.x/).

Some of these contracts use state variables for values that are meant to be constant so that they can be set during initialization.
When planning an upgrade, it is important to determine if part of the altered behaviour is based on some of these variables and update them as needed.

For example, superblock duration is one of such "constant" state variables in the [SuperblockClaims](contracts/SuperblockClaims.sol) contract.

Ideally, we would use `immutable` contract attributes for these, but the upgrades plugin does not support setting `immutable` attributes in constructors for logic/implementation contracts yet. See this [issue](https://github.com/OpenZeppelin/openzeppelin-upgrades/issues/312) for more details.

## License

MIT License<br/>
Copyright (c) 2021 Coinfabrik & Oscar Guindzberg<br/>
[License](LICENSE)

## Donations

BTC: 37gWZJPmEjM8RdgjauLsDUgbkYPe5bRFtt<br/>
ETH: 0xFc7E364035f52ecA68D71dcfb63D1E3769413d69<br/>
DOGE: D5q6QoN51z1daFpkreNqpbVq6i6oP6S35m

[dogethereum tools]: https://github.com/dogethereum/dogethereum-tools
[dogethereum agents]: https://github.com/dogethereum/dogethereum-agents
[scrypt-interactive]: https://github.com/dogethereum/scrypt-interactive
[ganache-cli]: https://www.npmjs.com/package/ganache-cli
[hardhat network]: https://hardhat.org/hardhat-network/
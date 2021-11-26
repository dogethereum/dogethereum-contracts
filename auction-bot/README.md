# Dogethereum Auction Bot

Bot that participates in the bidding process of new collateral auctions.

## Overview

Operators of the Dogethereum bridge need to deposit ether as collateral to be able to receive dogecoins.
If an operator behaves maliciously or falls under a certain doge-to-collateral threshold ratio, they will be liquidated.
When an operator is liquidated, an auction for the entirety of their collateral is started.
This bot monitors creation events of such auctions and bids in them.

Eventually, the auction will be closed by the bot if it has the winning bid. At this point, the bot receives the collateral in their address.

## Prerequisites

To run the bot you need to install the following:
- [nodejs](https://nodejs.org) [latest LTS](https://nodejs.org/en/about/releases/) or above. This is currently fermium (v14).

## Installing

To install the bot, you need to install the package itself from the repository. To do so:

- `cd` to the directory where the repo is cloned.
- `cd auction-bot`
- Execute `npm install`.

## Running the bot

### Configuration

To run the bot, you need to configure it first. There's a [sample](config/config.sample.json).

- `dbPath`: Path to the file where the database used by the bot is stored. If it doesn't exist, the bot will create it.
- `bidAmount`: The amount of DogeTokens that the bot will offer in any auction that is found.
- `auctionAddress`: The Ethereum address of the `DogeToken` contract. This contract is where auctions are processed.
- `bidderPrivateKey`: The Ethereum private key used by the bot to sign and send transactions with bids or closure of auctions.
- `ethereumNodeURL`: The URL to an Ethereum JSON-RPC endpoint. It is recommended to use a WebSocket URL, e.g. `ws://127.0.0.1:8545` assuming there's a local Ethereum node running.

The following are optional:
- `startingBlock`: Block tag or block number describing the block that the bot will use to start monitoring events. It is recommended to only set it when you need it.
- `numberOfConfirmations`: The bot will only watch for new events in blocks that have been confirmed at least this number of times.

### Starting up the bot

Once the bot is configured, all you need to do is run:
```sh
npm run start -- --config $PATH_TO_CONFIG
```
where `$PATH_TO_CONFIG` is the path of the configuration JSON you built in the previous step.

## Running the Tests

Tests are not defined within this package. Look at the auction bot tests in the `dogethereum-contracts` package if you want to run them. This package is currently in the root of the repository.
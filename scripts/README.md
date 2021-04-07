# Utilities for development

## Deployment of contracts

First compile contracts

```shell
    $ npx hardhat compile
```

Run migration scripts to deploy contracts

```shell
    $ npx hardhat run --network NETWORK scripts/deployDogethereum.ts
```

Where `NETWORK` can be

- `development`: Contract development without interacting with Dogecoin blockchain
- `integrationDogeRegtest`: Integration tests with Dogecoin regtest
- `integrationDogeMain`: Integration tests with Dogecoin main network
- `rinkeby`: Integration tests Rinkeby testnet and Dogecoin main network

## Initialize contracts

This step uses the network `integrationDogeRegtest`

```shell
    $ npx hardhat run --network integrationDogeRegtest scripts\init_contracts_local.ts
```

## Superblocks info

Display information for the last approved superblocks

```shell
    $ npx hardhat run --network NETWORK scripts\debug.ts
```

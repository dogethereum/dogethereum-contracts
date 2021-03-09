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

Where NETWORK can be

*   development: Contract development without interacting with Dogecoin blockchain
*   integrationDogeRegtest: Integration tests ganache and Dogecoin regtest
*   integrationDogeMain: Integration tests ganache and Dogecoin main network
*   rinkeby: Integration tests Rinkeby testnet and Dogecoin main network

Note: There's a ropsten network but currently contracts are too large to be
deployed with the gas limit of 4.7M gas.

## Initialize contracts

This steps depends on the NETWORK for integrationDogeRegtest

```shell
    $ npx hardhat run --network integrationDogeRegtest scripts\init_contracts_local.ts
```

## Superblocks info

Display information for the last approved superblocks

```shell
    $ npx hardhat run --network NETWORK scripts\debug.ts
```

## Send command to contracts

```shell
    $ npx hardhat --network NETWORK COMMAND [OPTIONS]
```

You can find dogethereum commands among Hardhat tasks by invoking `npx hardhat --help`. To see further options you can invoke the help for that particular task. E.g. for the `dogethereum:challenge` task you can invoke `npx hardhat dogethereum:challenge --help`.

Where COMMAND

*   `dogethereum:challenge`: Start a challenge to a superblock

    Available OPTIONS are:

    *   `--from ADDRESS`: Address used to send the challenge from.
        When not specified it will use the first account available in the runtime environment.

    *   `--superblock SUPERBLOCK_ID`: Superblock ID to challenge.
        When none is specified it will challenge the next superblock.
        If the superblock was not submitted it will wait for it.

    *   `--deposit AMOUNT`: It will deposit the amount of ether in the contract.
        If the balance is zero and no deposit is specified it
        will try to deposit 1000 wei.

# DogeRelay

DogeRelay is a set of contracts that enable sending coins from the Dogecoin blockchain to ethereum blockchain.
The core of this project are:
* [DogeRelay contract](contracts/DogeRelay.sol)
  * Keeps a copy of the Dogecoin blockchain (just the headers)
  * Informs [DogeToken contract](contracts/token/DogeToken.sol) when a Dogecoin transaction locked funds
  * Inspired on [BtcRelay](https://github.com/ethereum/btcrelay).
* [DogeToken contract](contracts/token/DogeToken.sol)
  * An ERC20 contract where 1 token is worth 1 Dogecoin.
  * Tokens are minted when coins are locked on the Dogecoin blockchain.


## Design

![Design](./design.png)


## Running the Tests

* Install prerequisites
  * [nodejs](https://nodejs.org) v9.2.0 or above.
  * [truffle](http://truffleframework.com/) v4.0.1 or above.
  * [ganache-cli](https://github.com/trufflesuite/ganache-cli) v6.0.3 or above.
  * Make truffle use solidity compiler v0.4.19 or above.
    * Open a terminal and go to the truffle folder
      * e.g. If you are on a mac, using nvm and node 9.2.0 `cd ~/.nvm/versions/node/v9.2.0/lib/node_modules/truffle/`
    * Edit package.json and update solc dependency version
      * ```
        "dependencies": {
          ...
          "solc": "^0.4.19"
          ...
        }
      ```
    * Run `npm install` on the truffle folder
* Clone this repo.
* Install npm dependencies.
  * cd to the directory where the repo is cloned.
  * ```
    npm install
    ```
* Run tests: 
  * ```
    # first start ganache-cli
    ganache-cli --gasLimit 4000000000000
    
    # run tests
    truffle test
    ```
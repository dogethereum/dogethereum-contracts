#!/bin/sh

# rm -rf build
# truffle compile
# truffle migrate --reset --network integrationDogeRegtest

truffle exec  --network integrationDogeRegtest scripts/init_contracts_local.js
truffle exec  --network integrationDogeRegtest scripts/debug.js

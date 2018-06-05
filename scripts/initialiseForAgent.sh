#!/bin/sh

# rm -rf build
# truffle compile
# truffle migrate --reset --network integrationDogeRegtest

truffle exec  --network integrationDogeRegtest scripts/init_dogerelay_regtest.js
truffle exec  --network integrationDogeRegtest scripts/debug.js

#!/bin/bash

set -eu

if [[ ! -v NETWORK ]]; then
  NETWORK="integrationDogeRegtest"
fi

# TODO port this to a Hardhat script
npx hardhat run --network "$NETWORK" scripts/init_contracts_local.ts
npx hardhat run --network "$NETWORK" scripts/debug.ts

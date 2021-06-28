#!/bin/bash

set -o nounset -o errexit

if [[ ! -v NETWORK ]]; then
  NETWORK="integrationDogeRegtest"
fi

# TODO port this to a Hardhat script?

# TODO: this should be a Hardhat task so it can accept parameters
npx hardhat run --network "$NETWORK" scripts/deployDogethereum.ts

# Init contracts: initial doge header and operator
npx hardhat run --network "$NETWORK" scripts/init_contracts_local.ts

# Print dogethereum contract system general status
npx hardhat run --network "$NETWORK" scripts/debug.ts

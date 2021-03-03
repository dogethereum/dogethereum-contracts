#!/bin/bash

set -eu

if [[ ! -v WEB3J ]]; then
  WEB3J="web3j"
fi

if [[ ! -v NETWORK ]]; then
  NETWORK="integrationDogeRegtest"
fi

npx hardhat compile --quiet
npx hardhat run --network $NETWORK ./scripts/deployDogethereum.ts


DEPLOYMENT_DIR="./deployment/$NETWORK"
if [[ ! -v OUTPUT_DIR ]]; then
  OUTPUT_DIR="$DEPLOYMENT_DIR/java-wrapper"
fi

$WEB3J solidity generate --abi "$DEPLOYMENT_DIR/abi/DogeToken.json" --outputDir "$OUTPUT_DIR" --package org.dogethereum.agents.contract
$WEB3J solidity generate --abi "$DEPLOYMENT_DIR/abi/DogeClaimManager.json" --outputDir "$OUTPUT_DIR" --package org.dogethereum.agents.contract
$WEB3J solidity generate --abi "$DEPLOYMENT_DIR/abi/DogeBattleManager.json" --outputDir "$OUTPUT_DIR" --package org.dogethereum.agents.contract
$WEB3J solidity generate --abi "$DEPLOYMENT_DIR/abi/DogeSuperblocks.json" --outputDir "$OUTPUT_DIR" --package org.dogethereum.agents.contract

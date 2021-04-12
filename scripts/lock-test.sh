#!/bin/bash

# Test sending doge to eth and back

# Declare variables
NETWORK="integrationDogeRegtest"

dogecoinQtProcessName=dogecoin-qt
dogecoinQtDatadir=.dogecoin-data
dogecoinQtExecutable=dogecoin-qt
dogecoinQtRpcuser=aaa
dogecoinQtRpcpassword=bbb

# TODO: we probably want to store all temporary data in a single directory so cleanup is straightforward.
if [[ ! -v agentRootDir ]]; then
    agentRootDir=/path/agentCodeDir
fi
if [[ ! -v agentDataDir ]]; then
    agentDataDir=/path/agentDataDir
fi
if [[ ! -v toolsRootDir ]]; then
    toolsRootDir=/path/toolsRootDir
fi
dogethereumDeploymentJson="deployment/$NETWORK/deployment.json"

# We avoid typechecking to speed up execution
export TS_NODE_TRANSPILE_ONLY=true

# Print instructions on the console
set -o xtrace -o nounset -o errexit
# Stop dogecoin-qt
DOGECOIN_PROCESSES="$(pgrep $dogecoinQtProcessName)" || echo "No dogecoin processes found"
if [[ $DOGECOIN_PROCESSES ]]; then
    kill "$DOGECOIN_PROCESSES"
    sleep 1s
fi
# Replace dogecoin-qt regtest datadir with the prepared db
rm -rf "$dogecoinQtDatadir/regtest/"
unzip "$agentRootDir/data/doge-qt-regtest-datadir.zip" -d "$dogecoinQtDatadir" > /dev/null 2>&1
# Start dogecoin-qt
$dogecoinQtExecutable -datadir="$dogecoinQtDatadir" -regtest -debug -server -listen -rpcuser=$dogecoinQtRpcuser -rpcpassword=$dogecoinQtRpcpassword -rpcport=41200 &
dogecoinNode=$!
sleep 4s
# Mine a doge block so dogecoin-qt is fully up and running
curl --user $dogecoinQtRpcuser:$dogecoinQtRpcpassword  --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "generate", "params": [1] }' -H 'content-type: text/plain;' http://127.0.0.1:41200/
# Clear agent data dir
# TODO: is this necessary?
rm -rf ${agentDataDir:?}/*
# Stop ganache
GANACHE_PROCESSES="$(pgrep --full '^node.*ganache-cli')" || echo "No ganache processes found"
if [[ $GANACHE_PROCESSES ]]; then
    # kill fails if passed an empty string
    kill "$GANACHE_PROCESSES"
    sleep 1s
fi
# Start ganache
npm run ganache > ganachelog.txt &
ganacheNode=$!
# Compile and deploy contracts
npx hardhat compile --quiet
# Deploy dogethereum to Ethereum network
rm -rf "deployment/$NETWORK"
npx hardhat run --network $NETWORK scripts/deployDogethereum.ts
# Init contracts: initial doge header and operator
npx hardhat run --network $NETWORK scripts/init_contracts_local.ts
# Print debug.js status
npx hardhat run --network $NETWORK scripts/debug.ts
echo "Please, start the agent..."
# Wait for agent to relay doge lock tx to eth and dogetokens minted
npx hardhat run --network $NETWORK scripts/wait_token_balance.ts

node "$toolsRootDir/user/lock.js" --deployment $dogethereumDeploymentJson --value 5000000000 --dogenetwork regtest --dogeport 41200 --dogeuser $dogecoinQtRpcuser --dogepassword $dogecoinQtRpcpassword

curl --user $dogecoinQtRpcuser:$dogecoinQtRpcpassword  --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "generate", "params": [10] }' -H 'content-type: text/plain;' http://127.0.0.1:41200/

# TODO: optimize this test once the agent manages to update and confirm the superblock and lock transaction fast enough
# Mine 5 eth blocks so unlock eth tx has enough confirmations
for j in {1..5}; do
    curl --request POST --data '{"jsonrpc":"2.0","method":"evm_mine","params":[],"id":74}' http://localhost:8545;
done

sleep 120s

# Mine 5 eth blocks so unlock eth tx has enough confirmations
for j in {1..5}; do
    curl --request POST --data '{"jsonrpc":"2.0","method":"evm_mine","params":[],"id":74}' http://localhost:8545;
done

sleep 120s

npx hardhat run --network $NETWORK scripts/debug.ts

kill $dogecoinNode $ganacheNode

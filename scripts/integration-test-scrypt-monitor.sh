#!/bin/bash

# Test sending doge to eth and back

# Declare variables
export NETWORK="integrationDogeScrypt"

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
if [[ ! -v scryptInteractiveDir ]]; then
    scryptInteractiveDir=/path/scryptInteractiveDir
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
# TODO: Move this to a launch agent script
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


# Deploy scrypt-interactive
pushd .
cd "$scryptInteractiveDir"
eval "$(npm run migrate:dev | grep "SCRYPT_.*_ADDRESS")"
if [[ ! -v SCRYPT_CLAIMS_ADDRESS ]]; then
    echo "Failure during scrypt-interactive deployment. Bailing out."
    kill $dogecoinNode $ganacheNode
    exit 1
fi
export SCRYPT_CHECKER=$SCRYPT_CLAIMS_ADDRESS

# The openethereum node is used to compute the scrypt hash algorithm.
# See the scrypt-interactive repository for more details.
# TODO: have this launch as part of the scrypt-interactive monitor?
# Stop openethereum
OPENETHEREUM_PROCESSES="$(pgrep 'openethereum')" || echo "No OpenEthereum processes found"
if [[ $OPENETHEREUM_PROCESSES ]]; then
    # kill fails if passed an empty string
    kill "$OPENETHEREUM_PROCESSES"
    sleep 1s
fi
# Start openethereum
npm run openethereum > openethereum.log 2>&1 &
openethereumNode=$!
popd


npx hardhat compile --quiet

# Deploy dogethereum to Ethereum network
rm -rf "deployment/$NETWORK"

# Setup contracts in blockchain
scripts/initialiseForAgent.sh

# Deposit collateral in ScryptClaims contract and launch defender
pushd .
cd "$scryptInteractiveDir"
# TODO: remove deposit once it is handled by the agents correctly
echo "Depositing ether in the ScryptClaims contract on behalf of the agent..."
npm start -- deposit 0.5
npm start -- defend > defender.log 2>&1 &
defenderProcess=$!
popd

# We're doing this here just to be able to synchronize with the dogethereum agent a few lines later.
# TODO: remove this by writing a new wait primitive
# Lock dogecoins with an operator
# All of these are fixed according to what the regtest datadir has
dogePrivateKey=cW9yAP8NRgGGN2qQ4vEQkvqhHFSNzeFPWTLBXriy5R5wf4KBWDbc
utxoTxid=34bae623d6fd05ac5d57045d0806c78e2f73f44261f0fb5ffe386cd130fad757
utxoIndex=0
utxoValue=$((450000 * 10 ** 8))
# The utxo value is expected in satoshis
node "$toolsRootDir/user/lock.js" --deployment $dogethereumDeploymentJson --ethereumAddress 0xa3a744d64f5136aC38E2DE221e750f7B0A6b45Ef --value 5000000000 --dogenetwork regtest --dogeport 41200 --dogeuser $dogecoinQtRpcuser --dogepassword $dogecoinQtRpcpassword --dogePrivateKey $dogePrivateKey --utxoTxid "$utxoTxid" --utxoIndex $utxoIndex --utxoValue $utxoValue
curl --user $dogecoinQtRpcuser:$dogecoinQtRpcpassword  --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "generate", "params": [10] }' -H 'content-type: text/plain;' http://127.0.0.1:41200/

echo "Please, start the agent..."

# Challenge the next superblock
npx hardhat --network integrationDogeScrypt dogethereum.challenge --challenger 0xB50a77BF193245E431b29CdD70b354119eb75Fd2 --deposit 1000000000

# Here the superblock agent is active and ready for tests

npx hardhat run --network $NETWORK scripts/debug.ts

# Wait for agent to relay doge lock tx to eth and dogetokens minted
npx hardhat run --network $NETWORK scripts/wait_token_balance.ts


# Mine 5 eth blocks so unlock eth tx has enough confirmations
# for j in {1..5}; do
#     curl --request POST --data '{"jsonrpc":"2.0","method":"evm_mine","params":[],"id":74}' http://localhost:8545;
# done

# Wait for manual tests
sleep 30000s

# Mine 10 doge blocks so doge unlock tx has enough confirmations
# curl --user $dogecoinQtRpcuser:$dogecoinQtRpcpassword  --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "generate", "params": [10] }' -H 'content-type: text/plain;' http://127.0.0.1:41200/



# Print status
# TODO: have it print challenge events
npx hardhat run --network $NETWORK scripts/debug.ts

kill $dogecoinNode $ganacheNode $defenderProcess $openethereumNode

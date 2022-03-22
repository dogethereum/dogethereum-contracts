#!/usr/bin/env bash

unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    *)          machine="UNKNOWN:${unameOut}"
esac

# Test sending doge to eth and back

# Declare variables
export NETWORK="integrationDogeRegtest"

if [ "$machine" == "Mac" ]; then
    dogecoinDatadir=.dogecoin-data
    if [[ -v USE_DOGECOIND ]]; then
        # TODO: add dogecoind path and process name for Mac
        echo "Unknown dogecoind executable path and process name"
        exit 1
    else
        dogecoinProcessName=Dogecoin-Qt
        dogecoinExecutable=/Applications/Dogecoin-Qt.app/Contents/MacOS/Dogecoin-Qt
    fi
elif [ "$machine" == "Linux" ]; then
    dogecoinDatadir=.dogecoin-data
    if [[ -v USE_DOGECOIND ]]; then
        dogecoinProcessName=dogecoind
        dogecoinExecutable=dogecoind
    else
        dogecoinProcessName=dogecoin-qt
        dogecoinExecutable=dogecoin-qt
    fi
else
    echo "Unexpected OS: $machine"
    exit 1
fi

dogecoinRpcuser=aaa
dogecoinRpcpassword=bbb
dogecoinRpcPort=41200

if [[ ! -v agentRootDir || ! -d $agentRootDir ]]; then
    echo 'Unknown agent root directory. Set the path to the agent root directory with the agentRootDir environment variable.'
    exit 1
fi
if [[ ! -v agentConfig || ! -f $agentConfig ]]; then
    echo 'Unknown agent config. Set the path to the agent config with the agentConfig environment variable.'
    exit 1
fi
if [[ ! -v toolsRootDir || ! -d $toolsRootDir ]]; then
    echo 'Unknown tools root directory. Set the path to the tools root directory with the toolsRootDir environment variable.'
    exit 1
fi
# TODO: we probably want to store all temporary data in a single directory so cleanup is straightforward.
if [[ ! -v agentDataDir ]]; then
    echo 'Unknown agent data directory. Set the path to the agent data directory with the agentDataDir environment variable.'
    exit 1
fi
dogethereumDeploymentJson="deployment/$NETWORK/deployment.json"

# We avoid typechecking to speed up execution
export TS_NODE_TRANSPILE_ONLY=true

export NODE_OPTIONS=--unhandled-rejections=strict

# Print instructions on the console
set -o nounset -o errexit # -o xtrace

function killIfRunning() {
    # kill fails if passed an empty string
    if [[ $# -gt 0 && -n $1 ]]; then
        kill "$@"
        sleep 1s
    fi
}

# Stop dogecoin-qt
DOGECOIN_PROCESSES="$(pgrep $dogecoinProcessName)" || echo "No dogecoin processes found"
killIfRunning "$DOGECOIN_PROCESSES"

# Replace dogecoin-qt regtest datadir with the prepared db
rm -rf "$dogecoinDatadir/regtest/"
unzip "$agentRootDir/data/doge-qt-regtest-datadir.zip" -d "$dogecoinDatadir" > /dev/null 2>&1
# Start dogecoin node
$dogecoinExecutable -datadir="$dogecoinDatadir" \
    -regtest \
    -debug \
    -server \
    -listen \
    -rpcuser=$dogecoinRpcuser \
    -rpcpassword=$dogecoinRpcpassword \
    -rpcport=$dogecoinRpcPort &
dogecoinNode=$!

# TODO: move this sleep into a typescript script that waits for the dogecoin node RPC interface to be available.
sleep 4s
# Mine a doge block so dogecoin-qt is fully up and running
curl --user $dogecoinRpcuser:$dogecoinRpcpassword \
    --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "generate", "params": [1] }' \
    --header 'content-type: text/plain;' \
    "http://127.0.0.1:$dogecoinRpcPort/"

# Clear agent data dir
# TODO: Move this to a launch agent script
rm -rf "${agentDataDir:?}"/*

# Stop previous ethereum node if it is still running
lingeringEthNode="$(pgrep -f '(^node.*ganache-cli)|(^node.*hardhat node)')" || \
    echo "No ethereum node processes found"
killIfRunning "$lingeringEthNode"

# Start ethereum node
if [[ -v USE_HH_NETWORK ]]; then
    challenger=0x9965507d1a55bcc2695c58ba16fb37d819b0a4dc
    npm run hh-network > hh-network.txt &
else
    challenger=0xB50a77BF193245E431b29CdD70b354119eb75Fd2
    npm run ganache > ganachelog.txt &
fi
ethNode=$!

# Compile and deploy contracts
npx hardhat compile --quiet

# Deploy dogethereum to Ethereum network
rm -rf "deployment/$NETWORK"

export SCRYPT_CHECKER="deploy_dummy"
# Setup contracts in blockchain
scripts/initialiseForAgent.sh

# Lock dogecoins with an operator
# All of these are fixed according to what the regtest datadir has
dogePrivateKey=cW9yAP8NRgGGN2qQ4vEQkvqhHFSNzeFPWTLBXriy5R5wf4KBWDbc
utxoTxid=34bae623d6fd05ac5d57045d0806c78e2f73f44261f0fb5ffe386cd130fad757
utxoIndex=0
utxoValue=$((450000 * 10 ** 8))
lockValue=5000000000
# The utxo value is expected in satoshis
lockTxs=$(node "$toolsRootDir/user/lock.js" \
    --deployment $dogethereumDeploymentJson \
    --ethereumAddress 0xa3a744d64f5136aC38E2DE221e750f7B0A6b45Ef \
    --value $lockValue \
    --dogenetwork regtest \
    --dogeport $dogecoinRpcPort \
    --dogeuser $dogecoinRpcuser \
    --dogepassword $dogecoinRpcpassword \
    --dogePrivateKey $dogePrivateKey \
    --utxoTxid "$utxoTxid" \
    --utxoIndex $utxoIndex \
    --utxoValue $utxoValue \
    --printTxJson)
curl --user $dogecoinRpcuser:$dogecoinRpcpassword \
    --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "generate", "params": [10] }' \
    --header 'content-type: text/plain;' \
    "http://127.0.0.1:$dogecoinRpcPort/"

pushd . > /dev/null 2>&1
cd "$agentRootDir"
lingeringAgent=$(pgrep -f 'exec:java -Ddogethereum.agents.conf.file=' -d " ") || \
    echo "No agent processes found"
killIfRunning $lingeringAgent
# Here we assume that the agent was already built
mvn exec:java "-Ddogethereum.agents.conf.file=$agentConfig" > agent.log 2>&1 &
agentPid=$!
popd > /dev/null 2>&1

# Challenge the next superblock
npx hardhat dogethereum.challenge \
    --network $NETWORK \
    --challenger $challenger \
    --deposit 1000000000 \
    --advance-battle true \
    --agent-pid $agentPid

# TODO: avoid hardcoding 10 seconds time delta here
# This should be enough to timeout the challenger
curl --request POST --data '{"jsonrpc":"2.0","method":"evm_increaseTime","params":[10],"id":"timeout-challenger"}' http://localhost:8545;
# It is necessary to mine a block so that the superblock defender agent sees that it can timeout the challenger
curl --request POST --data '{"jsonrpc":"2.0","method":"evm_mine","params":[],"id":"timeout-challenger"}' http://localhost:8545;
# Mine 10 doge blocks so doge unlock tx has enough confirmations
curl --user $dogecoinRpcuser:$dogecoinRpcpassword \
    --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "generate", "params": [10] }' \
    --header 'content-type: text/plain;' \
    "http://127.0.0.1:$dogecoinRpcPort/"

# Wait for agent to relay doge lock tx to eth and dogetokens minted
npx hardhat run --network $NETWORK scripts/wait_token_balance.ts

npx hardhat --network $NETWORK dogethereum.assertLock \
    --url "http://$dogecoinRpcuser:$dogecoinRpcpassword@127.0.0.1:$dogecoinRpcPort/" \
    --lock-value $lockValue \
    --tx-list "$lockTxs"
# TODO: assert token invariant

npx hardhat run --network $NETWORK scripts/debug.ts

# Prepare sender address to do unlocks
npx hardhat run --network $NETWORK scripts/prepare_sender.ts
for i in {1..2}; do
    # Print debug.js status
    npx hardhat run --network $NETWORK scripts/debug.ts

    # Send eth unlock tx
    unlockValue=300000000
    node "$toolsRootDir/user/unlock.js" \
        --deployment $dogethereumDeploymentJson \
        --privateKey 0xffd02f8d16c657add9aba568c83770cd3f06cebda3ddb544daf313002ca5bd53 \
        --receiver n2z4kV3rWPALTZz4sdoE5ag2UiErsrmJpJ \
        --value $unlockValue

    # Mine 5 eth blocks so unlock eth tx has enough confirmations
    for j in {1..5}; do
        curl --request POST \
            --data '{"jsonrpc":"2.0","method":"evm_mine","params":[],"id":"evm_mine_'"$i"'_'"$j"'"}' \
            http://localhost:8545;
    done

    # Wait for Eth to Doge agent to sign and broadcast doge unlock tx
    npx hardhat dogethereum.mineOnTx \
        --url "http://$dogecoinRpcuser:$dogecoinRpcpassword@127.0.0.1:$dogecoinRpcPort/" \
        --agent-pid $agentPid \

    # Wait for agent to relay doge unlock tx to eth and utxo length updated
    npx hardhat dogethereum.waitUtxo \
        --network $NETWORK \
        --operator-public-key-hash 0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6 \
        --utxo-length $((i + 1))

    # TODO: assert that $unlockValue doges minus fees was correctly sent to the expected address.
    # TODO: assert token invariant
done

# Print status after the unlocks were processed
npx hardhat run --network $NETWORK scripts/debug.ts

kill $agentPid $dogecoinNode $ethNode

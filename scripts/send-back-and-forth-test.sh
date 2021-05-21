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

# Lock dogecoins with an operator
# All of these are fixed according to what the regtest datadir has
dogePrivateKey=cW9yAP8NRgGGN2qQ4vEQkvqhHFSNzeFPWTLBXriy5R5wf4KBWDbc
utxoTxid=34bae623d6fd05ac5d57045d0806c78e2f73f44261f0fb5ffe386cd130fad757
utxoIndex=0
utxoValue=$((450000 * 10 ** 8))
# The utxo value is expected in satoshis
node "$toolsRootDir/user/lock.js" --deployment $dogethereumDeploymentJson --ethereumAddress 0xa3a744d64f5136aC38E2DE221e750f7B0A6b45Ef --value 5000000000 --dogenetwork regtest --dogeport 41200 --dogeuser $dogecoinQtRpcuser --dogepassword $dogecoinQtRpcpassword --dogePrivateKey $dogePrivateKey --utxoTxid "$utxoTxid" --utxoIndex $utxoIndex --utxoValue $utxoValue
curl --user $dogecoinQtRpcuser:$dogecoinQtRpcpassword  --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "generate", "params": [10] }' -H 'content-type: text/plain;' http://127.0.0.1:41200/

# Print debug.js status
npx hardhat run --network $NETWORK scripts/debug.ts
echo "Please, start the agent..."

# Wait for agent to relay doge lock tx to eth and dogetokens minted
npx hardhat run --network $NETWORK scripts/wait_token_balance.ts

npx hardhat run --network $NETWORK scripts/debug.ts

# Prepare sender address to do unlocks
npx hardhat run --network $NETWORK scripts/prepare_sender.ts
for i in {1..2}; do
	# Print debug.js status
	npx hardhat run --network $NETWORK scripts/debug.ts

	# Send eth unlock tx
	node "$toolsRootDir/user/unlock.js" --deployment $dogethereumDeploymentJson --privateKey 0xffd02f8d16c657add9aba568c83770cd3f06cebda3ddb544daf313002ca5bd53 --receiver n2z4kV3rWPALTZz4sdoE5ag2UiErsrmJpJ --value 300000000

	# Mine 5 eth blocks so unlock eth tx has enough confirmations
	for j in {1..5}; do
		curl --request POST --data '{"jsonrpc":"2.0","method":"evm_mine","params":[],"id":74}' http://localhost:8545;
	done

	# Wait for Eth to Doge agent to sign and broadcast doge unlock tx
	sleep 30s

	# Mine 10 doge blocks so doge unlock tx has enough confirmations
	curl --user $dogecoinQtRpcuser:$dogecoinQtRpcpassword  --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "generate", "params": [10] }' -H 'content-type: text/plain;' http://127.0.0.1:41200/

	# Wait for agent to relay doge unlock tx to eth and utxo length updated
	npx hardhat dogethereum.waitUtxo --network $NETWORK --operator-public-key-hash 0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6 --utxo-length $(($i + 1))
done

# Print status after the unlocks were processed
npx hardhat run --network $NETWORK scripts/debug.ts

kill $dogecoinNode $ganacheNode

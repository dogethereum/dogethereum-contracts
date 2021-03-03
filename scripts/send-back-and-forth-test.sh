#!/bin/bash

# Test sending doge to eth and back
# Tested on Mac OSX only

# Declare variables
dogecoinQtProcessName=Dogecoin-Qt
dogecoinQtDatadir=/Users/youruser/Library/Application\ Support/Dogecoin
dogecoinQtExecutable=/Applications/Dogecoin-Qt.app/Contents/MacOS/Dogecoin-Qt
dogecoinQtRpcuser=aaa
dogecoinQtRpcpassword=bbb
agentCodeDir=/path/agentCodeDir
agentDataDir=/path/agentDataDir
dogethereumContractsCodeDir=/path/dogethereumContractsCodeDir

NETWORK="integrationDogeRegtest"

# Print instructions on the console
set -o xtrace -o nounset
# Stop dogecoin-qt
killall $dogecoinQtProcessName
sleep 3s
# Replace dogecoin-qt regtest datadir with the prepared db
rm -rf "$dogecoinQtDatadir/regtest/"
unzip "$agentCodeDir/data/doge-qt-regtest-datadir.zip" -d "$dogecoinQtDatadir" > /dev/null 2>&1
# Start dogecoin-qt
$dogecoinQtExecutable -regtest -debug -server -listen -rpcuser=$dogecoinQtRpcuser -rpcpassword=$dogecoinQtRpcpassword -rpcport=41200 &
sleep 10s
# Mine a doge block so dogecoin-qt is fully up and running
curl --user $dogecoinQtRpcuser:$dogecoinQtRpcpassword  --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "generate", "params": [1] }' -H 'content-type: text/plain;' http://127.0.0.1:41200/
# Clear agent data dir
# TODO: is this necessary?
rm -rf ${agentDataDir:?}/*
# Restart ganache
kill "$(pgrep ganache)"
sleep 1s
npm run ganache > ganachelog.txt &
# Compile and deploy contracts
npx hardhat compile --quiet
npx hardhat run --network $NETWORK scripts/deployDogethereum.ts
# Init contracts: initial doge header and operator
npx hardhat run --network $NETWORK scripts/init_contracts_local.ts
# Print debug.js status
npx hardhat run --network $NETWORK scripts/debug.ts
echo "Please, start the agent..."
# Wait for agent to relay doge lock tx to eth and dogetokens minted
npx hardhat run --network $NETWORK scripts/wait_token_balance.ts
# Prepare sender address to do unlocks
npx hardhat run --network $NETWORK scripts/prepare_sender.ts
for i in {1..2}; do
	# Send eth unlock tx
	node ../dogethereum-tools/user/unlock.js --ethnetwork ganacheDogeRegtest --json $dogethereumContractsCodeDir/build/contracts/DogeToken.json --sender 0xd2394f3fad76167e7583a876c292c86ed10305da --receiver ncbC7ZY1K9EcMVjvwbgSBWKQ4bwDWS4d5P --value 300000000
	# Print debug.js status
	npx hardhat run --network $NETWORK scripts/debug.ts
	# Mine 5 eth blocks so unlock eth tx has enough confirmations
	for j in {1..5}; do
		curl -X POST --data '{"jsonrpc":"2.0","method":"evm_mine","params":[],"id":74}' http://localhost:8545;
	done
	# Wait for Eth to Doge agent to sign and broadcast doge unlock tx
	sleep 30s
	# Mine 10 doge blocks so doge unlock tx has enough confirmations
	curl --user $dogecoinQtRpcuser:$dogecoinQtRpcpassword  --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "generate", "params": [10] }' -H 'content-type: text/plain;' http://127.0.0.1:41200/
	# Wait for agent to relay doge unlock tx to eth and utxo length updated
	npx hardhat run --network $NETWORK scripts/wait_two_utxos.ts
done

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

# Print instructions on the console
set -o xtrace
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
rm -rf $agentDataDir/*
# Restart ganache
kill $(ps aux | grep ganache | grep -v grep | awk '{print $2}')
sleep 1s
ganache-cli --gasLimit 400000000000 > ganachelog.txt &
# Remove compiled contract to force recompiling
rm -rf $dogethereumContractsCodeDir/build/contracts/
# Compile and deploy contracts
truffle deploy --network integrationDogeRegtest | grep Error
# Init contracts: initial doge header and operator
truffle exec  --network integrationDogeRegtest scripts/init_contracts_local.js 
# Print debug.js status
truffle exec  --network integrationDogeRegtest scripts/debug.js 
echo "Please, start the agent..."
# Wait for agent to relay doge lock tx to eth and dogetokens minted
truffle exec  --network integrationDogeRegtest scripts/wait_token_balance.js 
# Prepare sender address to do unlocks
truffle exec  --network integrationDogeRegtest scripts/prepare_sender.js
for i in $(seq 1 2); do 
	# Send eth unlock tx 
	node ../dogethereum-tools/user/unlock.js --ethnetwork ganacheDogeRegtest --json $dogethereumContractsCodeDir/build/contracts/DogeToken.json --sender 0xd2394f3fad76167e7583a876c292c86ed10305da --receiver ncbC7ZY1K9EcMVjvwbgSBWKQ4bwDWS4d5P --value 300000000
	# Print debug.js status
	truffle exec  --network integrationDogeRegtest scripts/debug.js 
	# Mine 5 eth blocks so unlock eth tx has enought confirmations
	for j in $(seq 1 5); do 
		curl -X POST --data '{"jsonrpc":"2.0","method":"evm_mine","params":[],"id":74}' http://localhost:8545;
	done
	# Wait for Eth to Doge agent to sign and broadcast doge unlock tx
	sleep 30s
	# Mine 10 doge blocks so doge unlock tx has enough confirmations
	curl --user $dogecoinQtRpcuser:$dogecoinQtRpcpassword  --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "generate", "params": [10] }' -H 'content-type: text/plain;' http://127.0.0.1:41200/
	# Wait for agent to relay doge unlock tx to eth and utxo length updated
	truffle exec  --network integrationDogeRegtest scripts/wait_two_utxos.js 
done
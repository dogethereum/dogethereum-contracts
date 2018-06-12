#!/bin/sh

rm -rf build
truffle compile
truffle migrate --reset --network integrationDogeRegtest

/home/cat/software/web3j-3.3.1/bin/web3j truffle generate ~/dogethereum-contracts/build/contracts/DogeRelay.json -o ~/agent/src/main/java/ -p org.dogethereum.dogesubmitter.contract
/home/cat/software/web3j-3.3.1/bin/web3j truffle generate ~/dogethereum-contracts/build/contracts/DogeToken.json -o ~/agent/src/main/java/ -p org.dogethereum.dogesubmitter.contract
/home/cat/software/web3j-3.3.1/bin/web3j truffle generate ~/dogethereum-contracts/build/contracts/DogeClaimManager.json -o ~/agent/src/main/java/ -p org.dogethereum.dogesubmitter.contract
/home/cat/software/web3j-3.3.1/bin/web3j truffle generate ~/dogethereum-contracts/build/contracts/DogeSuperblocks.json -o ~/agent/src/main/java/ -p org.dogethereum.dogesubmitter.contract

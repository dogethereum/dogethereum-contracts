#!/usr/bin/env node

const fs = require("fs");
const solc = require('solc');
const linker = require('solc/linker');
let Web3 = require('web3');

let web3 = new Web3();
web3.setProvider(new web3.providers.HttpProvider('http://localhost:8545'));

let input = {
    'DogeParser/DogeTx.sol' : fs.readFileSync('./contracts/DogeParser/DogeTx.sol', 'utf8'),
    'DogeProcessor.sol' : fs.readFileSync('./contracts/DogeProcessor.sol', 'utf8'),
    'IDogeRelay.sol' : fs.readFileSync('./contracts/IDogeRelay.sol', 'utf8'),
    'IScryptChecker.sol' : fs.readFileSync('./contracts/IScryptChecker.sol', 'utf8'),
    'ScryptCheckerDummy.sol' : fs.readFileSync('./contracts/ScryptCheckerDummy.sol', 'utf8'),
    'TransactionProcessor.sol' : fs.readFileSync('./contracts/TransactionProcessor.sol', 'utf8'),
    'DogeRelay.sol' : fs.readFileSync('./contracts/DogeRelay.sol', 'utf8'),
    'DogeRelayForTests.sol' : fs.readFileSync('./contracts/DogeRelayForTests.sol', 'utf8'),
    'DogeSuperblocks.sol' : fs.readFileSync('./contracts/DogeSuperblocks.sol', 'utf8'),
    'DogeBattleManager.sol' : fs.readFileSync('./contracts/DogeBattleManager.sol', 'utf8'),
    'DogeClaimManager.sol' : fs.readFileSync('./contracts/DogeClaimManager.sol', 'utf8'),
    'DogeDepositsManager.sol' : fs.readFileSync('./contracts/DogeDepositsManager.sol', 'utf8'),
    'DogeErrorCodes.sol' : fs.readFileSync('./contracts/DogeErrorCodes.sol', 'utf8'),
    'token/DogeToken.sol' : fs.readFileSync('./contracts/token/DogeToken.sol', 'utf8'),
    'token/Token.sol' : fs.readFileSync('./contracts/token/Token.sol', 'utf8'),
    'token/StandardToken.sol' : fs.readFileSync('./contracts/token/StandardToken.sol', 'utf8'),
    'token/HumanStandardToken.sol' : fs.readFileSync('./contracts/token/HumanStandardToken.sol', 'utf8'),
    'token/Set.sol' : fs.readFileSync('./contracts/token/Set.sol', 'utf8')
};

let compiledContract = solc.compile({sources: input, gasLimit: "8990000000000000"}, 1);
let abi;

let bytecode;
let gasEstimate = 0;

let deployedContracts = [
    'DogeRelay.sol:DogeRelay',
    'DogeSuperblocks.sol:DogeSuperblocks',
    'DogeClaimManager.sol:DogeClaimManager',
    'TransactionProcessor.sol:TransactionProcessor',
    'ScryptCheckerDummy.sol:ScryptCheckerDummy',
    'DogeProcessor.sol:DogeProcessor'
];

for (i in deployedContracts) {
    d = deployedContracts[i];
    // console.log(compiledContract, Object.keys(compiledContract.contracts));
    bytecode = '0x' + compiledContract.contracts[d].bytecode;
    let gas = web3.eth.estimateGas({data: bytecode, gasLimit: "8990000000000000"});
    console.log("Gas for " + d + ": " + gas);
    gasEstimate += gas;
}


bytecode = '0x' + compiledContract.contracts['token/DogeToken.sol:DogeToken'].bytecode;
bytecode = linker.linkBytecode(bytecode, {'token/Set.sol:Set': '0x0'});

let gas = web3.eth.estimateGas({data: bytecode});
console.log("Gas for token/DogeToken.sol:DogeToken: " + gas);
gasEstimate += gas;

console.log("Total gas: " + gasEstimate);

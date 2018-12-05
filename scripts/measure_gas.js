#!/usr/bin/env node

const fs = require("fs");
const solc = require('solc');
const linker = require('solc/linker');
let Web3 = require('web3');

let web3 = new Web3();
web3.setProvider(new web3.providers.HttpProvider('http://localhost:8545'));

let input = {
    'DogeParser/DogeMessageLibrary.sol' : fs.readFileSync('./contracts/DogeParser/DogeMessageLibrary.sol', 'utf8'),
    'IScryptChecker.sol' : fs.readFileSync('./contracts/IScryptChecker.sol', 'utf8'),
    'IScryptCheckerListener.sol' : fs.readFileSync('./contracts/IScryptCheckerListener.sol', 'utf8'),
    'ScryptCheckerDummy.sol' : fs.readFileSync('./contracts/ScryptCheckerDummy.sol', 'utf8'),
    'TransactionProcessor.sol' : fs.readFileSync('./contracts/TransactionProcessor.sol', 'utf8'),
    'DogeBattleManager.sol' : fs.readFileSync('./contracts/DogeBattleManager.sol', 'utf8'),
    'DogeClaimManager.sol' : fs.readFileSync('./contracts/DogeClaimManager.sol', 'utf8'),
    'DogeDepositsManager.sol' : fs.readFileSync('./contracts/DogeDepositsManager.sol', 'utf8'),
    'DogeErrorCodes.sol' : fs.readFileSync('./contracts/DogeErrorCodes.sol', 'utf8'),
    'DogeSuperblocks.sol' : fs.readFileSync('./contracts/DogeSuperblocks.sol', 'utf8'),
    'ECRecovery.sol' : fs.readFileSync('./contracts/ECRecovery.sol', 'utf8'),
    'token/DogeToken.sol' : fs.readFileSync('./contracts/token/DogeToken.sol', 'utf8'),
    'token/Token.sol' : fs.readFileSync('./contracts/token/Token.sol', 'utf8'),
    'token/StandardToken.sol' : fs.readFileSync('./contracts/token/StandardToken.sol', 'utf8'),
    'token/HumanStandardToken.sol' : fs.readFileSync('./contracts/token/HumanStandardToken.sol', 'utf8'),
    'token/Set.sol' : fs.readFileSync('./contracts/token/Set.sol', 'utf8'),
    'openzeppelin-solidity/contracts/math/SafeMath.sol' :
        fs.readFileSync('./node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol', 'utf8')
};

let deployedContracts = {
    'DogeBattleManager.sol:DogeBattleManager' : {'DogeParser/DogeMessageLibrary.sol:DogeMessageLibrary': '0x0'},
    'DogeClaimManager.sol:DogeClaimManager' : {},
    'DogeSuperblocks.sol:DogeSuperblocks' : {'DogeParser/DogeMessageLibrary.sol:DogeMessageLibrary': '0x0'},
    'token/DogeToken.sol:DogeToken' : {'token/Set.sol:Set': '0x1'}
};

// TODO: make deployment gas limit variable for each contract

/**
 * @param {Object.<string, string>} sources
 *        Mapping containing all contract sources to be compiled.
 *        Key: relative contract paths, e.g. "token/MyToken.sol".
 *        Value: contract source code,
 *        e.g. fs.readFileSync("./contracts/token/MyToken.sol").
 * @param {string} compilationGasLimit
 *        Gas limit for compiling each contract.
 *        It's a string because it must be passed as an argument to solc.compile
 *        and JavaScript's integer size limit might be too small.
 * @param {string} deploymentGasLimit
 *        Gas limit for deploying each contract.
 * @param {Object.<string, Object.<string, string>} deployedContracts
 *        Mapping containing the dependencies for each contract to be deployed.
 *        Key: relative contract path, e.g. "token/MyToken.sol".
 *        Value: another mapping where each key is a contract path, e.g. "token/Set.sol",
 *        and each value is said contract's address, e.g. "0x0".
 *        Every contract in this mapping must be included in the sources.
 */
function measureDeploymentGasPerContract(
    sources,
    compilationGasLimit,
    deploymentGasLimit,
    deployedContracts
) {
    let compiledContracts = solc.compile({
        sources: input,
        gasLimit: compilationGasLimit
    }, 1);
    let bytecode;
    let gasPerContract = [];

    for (contract in deployedContracts) {
        dependencies = deployedContracts[contract];
        bytecode = '0x' + compiledContracts.contracts[contract].bytecode;
        
        if (Object.keys(dependencies).length > 0) {
            bytecode = linker.linkBytecode(bytecode, dependencies);
        }
        
        gasPerContract[contract] = web3.eth.estimateGas({
            data: bytecode,
            gasLimit: deploymentGasLimit
        });
    }

    return gasPerContract;
}

function measureTotalDeploymentGas(
    sources,
    compilationGasLimit,
    deploymentGasLimit,
    deployedContracts
) {
    let deploymentGasPerContract = measureDeploymentGasPerContract(
        sources,
        compilationGasLimit,
        deploymentGasLimit,
        deployedContracts
    );
    let totalGas = 0;
    
    for (contract in deploymentGasPerContract) {
        totalGas += deploymentGasPerContract[contract];
    }

    return totalGas;
}

async function measureFunctionGas(
    compiledContracts,
    contractName,
    dependencies,
    func,
    args,
    callGas
) {
    let contract = compiledContracts.contracts[contractName];
    let bytecode = contract.bytecode;
    bytecode = linker.linkBytecode(bytecode, dependencies);
    let abi = JSON.parse(contract.interface);
    let createdContract = web3.eth.contract(abi);
    var returnedGas;

    await createdContract.new({
        from: web3.eth.coinbase,
        gas: callGas,
        data: '0x' + bytecode
    }, measureFunctionGasCallback);

    return returnedGas;

    function measureFunctionGasCallback(err, myContract) {
        if (err) {
            console.log(err);
            return;
        }
    
        if (myContract.address != undefined) {
            let methodSignature = myContract[func].getData.apply(myContract[func], args);
            
            let callbackGas = web3.eth.estimateGas({
                from: web3.eth.coinbase,
                to: myContract.address,
                data: methodSignature,
                gas: callGas
            });
    
            returnedGas = callbackGas;
        }
    }
}

async function main() {
    let compiledContracts = solc.compile({sources: input, gasLimit: "8900000000"}, 1);
    
    let gas = await measureFunctionGas(
        compiledContracts,
        "DogeSuperblocks.sol:DogeSuperblocks",
        {'DogeParser/DogeMessageLibrary.sol:DogeMessageLibrary': '0x0'},
        "setClaimManager",
        ["0x1"],
        1000000000
    );

    console.log(gas);
}

main();
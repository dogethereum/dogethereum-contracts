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

let contractDeploymentInfo = {
    'DogeBattleManager.sol:DogeBattleManager' : {
        dependencies: {'DogeParser/DogeMessageLibrary.sol:DogeMessageLibrary': '0x0'},
        deploymentGasLimit: "80000000"
    },

    'DogeClaimManager.sol:DogeClaimManager' : {
        dependencies: {},
        deploymentGasLimit: "80000000"
    },
    
    'DogeSuperblocks.sol:DogeSuperblocks' : {
        dependencies: {'DogeParser/DogeMessageLibrary.sol:DogeMessageLibrary': '0x0'},
        deploymentGasLimit: "80000000"
    },
    
    'token/DogeToken.sol:DogeToken' : {
        dependencies: {'token/Set.sol:Set': '0x1'},
        deploymentGasLimit: "80000000"
    }
};

/**
 * Object containing a contract's deployment dependencies
 * and deployment gas limit.
 * @typedef {{dependencies: contractToAddr, deploymentGasLimit: string}} deploymentInfo
 */

/**
 * @typedef {Object.<string, string>} contractToAddr
 */

/**
 * @typedef {{args: string[], callGas: string}} callInfo
 */

/**
 * Measures deployment gas usage for each contract.
 * @param {Object} compiledContracts
 * Output of solc.compile(...) with the contracts to be deployed
 * as its sources.
 * @param {Object.<string, deploymentInfo>} contractDeploymentInfo
 * Mapping containing the dependencies and deployment gas limit
 * for each contract to be deployed.
 * @returns {Object.<string, int>}
 * Mapping: contract name -> gas usage
 */
function measureDeploymentGasPerContract(compiledContracts, contractDeploymentInfo) {
    let bytecode;
    let gasPerContract = [];

    for (contract in contractDeploymentInfo) {
        dependencies = contractDeploymentInfo[contract].dependencies;
        bytecode = '0x' + compiledContracts.contracts[contract].bytecode;
        
        if (Object.keys(dependencies).length > 0) {
            bytecode = linker.linkBytecode(bytecode, dependencies);
        }
        
        gasPerContract[contract] = web3.eth.estimateGas({
            data: bytecode,
            gasLimit: contractDeploymentInfo[contract].deploymentGasLimit
        });
    }

    return gasPerContract;
}

/**
 * Measures gas usage for deploying all contracts.
 * @param {Object} compiledContracts
 * Output of solc.compile(...) with the contracts to be deployed
 * as its sources.
 * @param {Object.<string, deploymentInfo>} contractDeploymentInfo
 * Mapping containing the dependencies and deployment gas limit
 * for each contract to be deployed.
 * @returns {int}
 * Total deployment gas usage.
 */
function measureTotalDeploymentGas(compiledContracts, contractDeploymentInfo) {
    let totalGas = 0;
    let deploymentGasPerContract = measureDeploymentGasPerContract(
        compiledContracts,
        contractDeploymentInfo
    );
    
    for (contract in deploymentGasPerContract) {
        totalGas += deploymentGasPerContract[contract];
    }

    return totalGas;
}

/**
 * Measures gas usage for a set of functions from a single contract.
 * Deploys contract first.
 * @param {Object} compiledContracts
 * Output of solc.compile(...) with the contract the functions belong to
 * as one of its sources.
 * @param {string} contractName
 * Name of the contract that the functions belong to,
 * e.g. "token/MyToken.sol:MyToken".
 * @param {contractToAddr} dependencies
 * Deployment dependencies for the contract.
 * @param {Object.<string, callInfo>} functionInfo
 * Mapping containing the arguments and call gas limit
 * for each function.
 */
async function measureFunctionGas(
    compiledContracts,
    contractName,
    contractCreationGas,
    dependencies,
    functionInfo
) {
    let contract = compiledContracts.contracts[contractName];
    let bytecode = contract.bytecode;
    bytecode = linker.linkBytecode(bytecode, dependencies);
    let abi = JSON.parse(contract.interface);
    let createdContract = web3.eth.contract(abi);
    let returnedMap = await new Promise((resolve, reject) => {
        createdContract.new({
            from: web3.eth.coinbase,
            gas: contractCreationGas,
            data: '0x' + bytecode
        }, (err, myContract) => {
            if (err) {
                console.log(err);
                return reject(err);
            }

            let gasPerFunction = [];

            if (myContract.address != undefined) {
                for (functionName in functionInfo) {
                    let methodSignature = myContract[functionName].getData.apply(
                        myContract[functionName],
                        functionInfo[functionName].args
                    );
                    
                    let gas = web3.eth.estimateGas({
                        from: web3.eth.coinbase,
                        to: myContract.address,
                        data: methodSignature,
                        gas: functionInfo[functionName].callGas
                    });

                    gasPerFunction[functionName] = gas;
                }
        
                resolve(gasPerFunction);
            }
        });
    });

    return returnedMap;
}

let functions = {
    "setClaimManager" : {
        args: ["0x1"],
        callGas: "1000000000"
    },

    "getBestSuperblock" : {
        args: [],
        callGas: "10000000"
    }
}

// TODO: implement
async function measureBatchFunctionGas(
    compiledContracts,
    contractDeploymentInfo,
    contractFunctions
) {
    let contract;
    let dependencies;
    let abi;

    // Deploy contracts
    for (contractName in contractDeploymentInfo) {
        contract = compiledContracts.contracts[contractName];
        dependencies = contractDeploymentInfo[contractName].dependencies;
        abi = JSON.parse(contract.interface);
        let bytecode = '0x' + contract.bytecode;
        if (Object.keys(dependencies).length > 0) {
            bytecode = linker.linkBytecode(bytecode, dependencies);
        }
    }

    // let gasPerFunction = [];
    // let functionContract;

    // for (functionName in functions) {
    //     functionContract = functions[functionName].contract;
    //     measureFunctionGas(
    //         compiledContracts,
    //         functionContract,
    //         contractDeploymentInfo[functionContract].gas
    //     );
    // }
}

async function main() {
    let compiledContracts = solc.compile({sources: input, gasLimit: "8900000000"}, 1);
    let gasPerFunction = await measureFunctionGas(
        compiledContracts,
        "DogeSuperblocks.sol:DogeSuperblocks",
        "100000000",
        {'DogeParser/DogeMessageLibrary.sol:DogeMessageLibrary': '0x0'},
        functions
    );
    console.log(gasPerFunction);
    // let totalGas = measureTotalDeploymentGas(compiledContracts, contractDeploymentInfo);
    // console.log(totalGas);
    // measureBatchFunctionGas(compiledContracts, contractDeploymentInfo, functions);
    
    // let gas = await measureFunctionGas(
    //     compiledContracts,
    //     "DogeSuperblocks.sol:DogeSuperblocks",
    //     {'DogeParser/DogeMessageLibrary.sol:DogeMessageLibrary': '0x0'},
    //     "setClaimManager",
    //     ["0x1"],
    //     "1000000000"
    // );

    // console.log(gas);
}

main();
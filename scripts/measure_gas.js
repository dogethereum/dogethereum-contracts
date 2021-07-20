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
    'SuperblockClaims.sol' : fs.readFileSync('./contracts/SuperblockClaims.sol', 'utf8'),
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

let superblockClaimsDeploymentInfo = {
    dependencies: {},
    deploymentGasLimit: "80000000"
};

let dogeSuperblocksDeploymentInfo = {
    dependencies: {'DogeParser/DogeMessageLibrary.sol:DogeMessageLibrary': '0x0'},
    deploymentGasLimit: "80000000"
};

let contractDeploymentInfo = {
    'DogeBattleManager.sol:DogeBattleManager' : {
        dependencies: {'DogeParser/DogeMessageLibrary.sol:DogeMessageLibrary': '0x0'},
        deploymentGasLimit: "80000000"
    },

    'SuperblockClaims.sol:SuperblockClaims' : superblockClaimsDeploymentInfo,
    
    'DogeSuperblocks.sol:DogeSuperblocks' : dogeSuperblocksDeploymentInfo,
    
    'token/DogeToken.sol:DogeToken' : {
        dependencies: {'token/Set.sol:Set': '0x1'},
        deploymentGasLimit: "80000000"
    }
};


/**
 * @typedef {Object.<string, string>} ContractToAddr
 */

/**
 * Object containing a contract's deployment dependencies
 * and deployment gas limit.
 * @typedef {{dependencies: contractToAddr, deploymentGasLimit: string}} DeploymentInfo
 */

/**
 * @typedef {{args: string[], callGas: string}} FunctionInfo
 */

/**
 * Object containing a contract's deployment dependencies and gas limit
 * and a mapping of function names from the contract to their call arguments and call gas.
 * @typedef {{deploymentInfo: deploymentInfo, functions: Object.<string, callInfo>}} DeploymentAndFunctions
 */

/**
 * Measures deployment gas usage for each contract.
 * @param {Object} compiledContracts
 * Output of solc.compile(...) with the contracts to be deployed
 * as its sources.
 * @param {Object.<string, DeploymentInfo>} contractDeploymentInfo
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

// TODO: map arguments as well as function name

/**
 * Measures gas usage for a set of functions from a single contract.
 * Deploys contract first.
 * @param {Object} compiledContracts
 * Output of solc.compile(...) with the contract the functions belong to
 * as one of its sources.
 * @param {string} contractName
 * Name of the contract that the functions belong to,
 * e.g. "token/MyToken.sol:MyToken".
 * @param {ContractToAddr} dependencies
 * Deployment dependencies for the contract.
 * @param {Object.<string, FunctionInfo>} functionInfo
 * Mapping containing the arguments and call gas limit
 * for each function.
 * @returns {Object.<string, int>}
 * Mapping: function name -> gas usage
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

/**
 * Measures gas usage for several function sets belonging to different contracts.
 * @param {Object} compiledContracts
 * Output of solc.compile(...) with the contracts to be deployed
 * as its sources.
 * @param {Object.<string, DeploymentAndFunctions>} contractInfo
 * Mapping containing the dependencies, deployment gas limit
 * and functions to be called for each contract.
 */
async function measureBatchFunctionGas(compiledContracts, contractInfo) {
    let functionsPerContract = [];
    let deploymentInfo;

    for (contractName in contractInfo) {
        deploymentInfo = contractInfo[contractName].deploymentInfo;
        let gasPerFunction = await measureFunctionGas(
            compiledContracts,
            contractName,
            deploymentInfo.deploymentGasLimit,
            deploymentInfo.dependencies,
            contractInfo[contractName].functions
        );
        functionsPerContract[contractName] = gasPerFunction;
    }

    return functionsPerContract;
}

let dogeSuperblocksFunctions = {
    "setSuperblockClaims" : {
        args: ["0x1"],
        callGas: "1000000000"
    },

    "getBestSuperblock" : {
        args: [],
        callGas: "10000000"
    }
}

let superblockClaimsFunctions = {
    "getClaimSubmitter" : {
        args: ["0xc48beef32273a1cf1be0df0db9cea15cf798faecbe548574b07ceeb24f4e4293"],
        callGas: "1000000"
    },

    "getClaimExists" : {
        args: ["0xc48beef32273a1cf1be0df0db9cea15cf798faecbe548574b07ceeb24f4e4293"],
        callGas: "1000000"
    }
}

let contractInfo = {
    "DogeSuperblocks.sol:DogeSuperblocks" : {
        deploymentInfo: dogeSuperblocksDeploymentInfo,
        functions: dogeSuperblocksFunctions
    },

    "SuperblockClaims.sol:SuperblockClaims" : {
        deploymentInfo: superblockClaimsDeploymentInfo,
        functions: superblockClaimsFunctions
    }
};

async function main() {
    let compiledContracts = solc.compile({sources: input, gasLimit: "8900000000"}, 1);
    let functionGasPerContract = await measureBatchFunctionGas(compiledContracts, contractInfo);
    // let gasPerFunction = await measureFunctionGas(
    //     compiledContracts,
    //     "DogeSuperblocks.sol:DogeSuperblocks",
    //     "100000000",
    //     {'DogeParser/DogeMessageLibrary.sol:DogeMessageLibrary': '0x0'},
    //     functions
    // );
    console.log(functionGasPerContract);
    // let totalGas = measureTotalDeploymentGas(compiledContracts, contractDeploymentInfo);
    // console.log(totalGas);
    // measureBatchFunctionGas(compiledContracts, contractDeploymentInfo, functions);
    
    // let gas = await measureFunctionGas(
    //     compiledContracts,
    //     "DogeSuperblocks.sol:DogeSuperblocks",
    //     {'DogeParser/DogeMessageLibrary.sol:DogeMessageLibrary': '0x0'},
    //     "setSuperblockClaims",
    //     ["0x1"],
    //     "1000000000"
    // );

    // console.log(gas);
}

main();
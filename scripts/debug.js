var DogeSuperblocks = artifacts.require("./DogeSuperblocks.sol");
var DogeClaimManager = artifacts.require("./DogeClaimManager.sol");
var DogeToken = artifacts.require("./token/DogeToken.sol");
var utils = require('../test/utils');

module.exports = async function(callback) {
  var ds  = await DogeSuperblocks.deployed();
  var dcm  = await DogeClaimManager.deployed();
  console.log("Superblocks");
  console.log("---------");
  var bestSuperblockHash = await ds.getBestSuperblock.call(); 
  console.log("Best superblock hash : " + bestSuperblockHash.toString(16));
  var bestSuperblockHeight = await ds.getSuperblockHeight.call(bestSuperblockHash);
  console.log("Best superblock height : " + bestSuperblockHeight);
  var lastHash = await ds.getSuperblockLastHash.call(bestSuperblockHash);
  console.log("lastHash : " + lastHash);
  var indexNextSuperblock = await ds.getIndexNextSuperblock.call();
  console.log("indexNextSuperblock : " + indexNextSuperblock);
  var newSuperblockEventTimestamp = await dcm.getNewSuperblockEventTimestamp.call(bestSuperblockHash);
  console.log("newSuperblockEventTimestamp : " + newSuperblockEventTimestamp);
  console.log("");


  console.log("DogeToken");
  console.log("---------");
  var dt = await DogeToken.deployed();
  var balance1 = await dt.balanceOf.call("0x92ecc1ba4ea10f681dcf35c02f583e59d2b99b4b"); 
  console.log("DogeToken Balance of 0x92ecc1ba4ea10f681dcf35c02f583e59d2b99b4b : " + balance1);
  var balance2 = await dt.balanceOf.call("0xd2394f3fad76167e7583a876c292c86ed10305da"); 
  console.log("DogeToken Balance of 0xd2394f3fad76167e7583a876c292c86ed10305da : " + balance2);
  var balance3 = await dt.balanceOf.call("0xf5fa014271b7971cb0ae960d445db3cb3802dfd9"); 
  console.log("DogeToken Balance of 0xf5fa014271b7971cb0ae960d445db3cb3802dfd9 : " + balance3);


  var dogeEthPrice = await dt.dogeEthPrice.call(); 
  console.log("Doge-Eth price : " + dogeEthPrice);

  // Operators
  const operatorsLength = await dt.getOperatorsLength();
  console.log("operators length : " + operatorsLength);
  for (var i = 0; i < operatorsLength; i++) {      
    let operatorKey = await dt.operatorKeys(i);
    if (operatorKey[1] == false) {
      // not deleted
      let operatorPublicKeyHash = operatorKey[0];
      let operator = await dt.operators(operatorPublicKeyHash);
      console.log("operator [" + operatorPublicKeyHash + "]: " + 
                  "eth address : " + operator[0].toString(16) + ", " + 
                  "dogeAvailableBalance : " + operator[1] + ", " + 
                  "dogePendingBalance : " + operator[2] + ", " + 
                  "nextUnspentUtxoIndex : " + operator[3] + ", " + 
                  "ethBalance : " + web3.fromWei(operator[4]));
      const utxosLength = await dt.getUtxosLength(operatorPublicKeyHash);
      console.log("utxosLength : " + utxosLength);  
      for (var j = 0; j < utxosLength; j++) {
        var utxo = await dt.getUtxo(operatorPublicKeyHash, j);
        console.log("utxo [" + j + "]: " + utils.formatHexUint32(utxo[1].toString(16)) + ", " + utxo[2] + ", " + utxo[0]);  
      }    
    }
  }
 
  // Current block number 
  var ethBlockNumber = await web3.eth.getBlockNumber();
  console.log("Eth Current block : " + ethBlockNumber);

  // Unlock events
  var unlockRequestEvent = dt.UnlockRequest({}, {fromBlock: 0, toBlock: "latest"});
  var myResults = unlockRequestEvent.get(async function(error, unlockRequestEvents){ 
     if (error) console.log("error : " + error);
     console.log("unlockRequestEvents length : " + unlockRequestEvents.length);
     for (var i = 0; i < unlockRequestEvents.length; i++) {
        console.log("unlockRequestEvent [" + unlockRequestEvents[i].args.id + "]: ");
        console.log("  tx block number : " + unlockRequestEvents[i].blockNumber);
        var unlock = await dt.getUnlockPendingInvestorProof(unlockRequestEvents[i].args.id);
        console.log("  from : " + unlock[0]);
        console.log("  dogeAddress : " + unlock[1]);
        console.log("  value : " + unlock[2].toNumber());
        console.log("  operator fee : " + unlock[3].toNumber());
        console.log("  timestamp : " + unlock[4].toNumber());
        console.log("  selectedUtxos : ");
        for (var j = 0; j <  unlock[5].length; j++) {
          console.log("    " + unlock[5][j]);          
        }
        console.log("  doge tx fee : " + unlock[6].toNumber());
        console.log("  operatorPublicKeyHash : " + unlock[7]);
     }
  });
}
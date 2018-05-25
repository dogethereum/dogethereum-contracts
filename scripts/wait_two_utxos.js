var DogeToken = artifacts.require("./token/DogeToken.sol");

var dt;

module.exports = async function(callback) {
  dt = await DogeToken.deployed();
  await waitUtxosLength();
}

async function waitUtxosLength() {
  var utxosLength = await getAndPrintUtxosLength(dt);
  if (utxosLength <= 1) {
    setTimeout(waitUtxosLength, 10000);    
  }
}

async function getAndPrintUtxosLength(dt) {
  const operatorPublicKeyHash = '0x03cd041b0139d3240607b9fd1b2d1b691e22b5d6';
  let utxosLength = await dt.getUtxosLength(operatorPublicKeyHash);
  console.log("Utxo length of operator " + operatorPublicKeyHash + " : " + utxosLength);       
  return utxosLength;
}
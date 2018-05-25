var DogeToken = artifacts.require("./token/DogeToken.sol");

var dt;

module.exports = async function(callback) {
  dt = await DogeToken.deployed();
  await waitBalance();
}

async function waitBalance() {
  var balance = await getAndPrintBalance(dt);
  if (balance == 0) {
    setTimeout(waitBalance, 10000);    
  }
}

async function getAndPrintBalance(dt) {
  let balance = await dt.balanceOf.call("0xd2394f3fad76167e7583a876c292c86ed10305da"); 
  //balance = balance.toNumber();
  console.log("Token balance of 0xd2394f3fad76167e7583a876c292c86ed10305da: " + balance);       
  return balance;
}
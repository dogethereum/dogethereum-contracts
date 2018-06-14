var DogeToken = artifacts.require("./token/DogeToken.sol");
var process = require('process');
const utils = require('./utils');

module.exports = async function(callback) {
  var argv = process.argv;

  var sender = utils.getCliParam(argv, 0);
  var receiver = utils.getCliParam(argv, 1);
  var valueToTransfer = utils.getCliParam(argv, 2);

  console.log("Transfer " + utils.dogeToSatoshi(valueToTransfer) + " doge tokens from " + sender + " to " + receiver);

  // Do some checks
  if (!await utils.doSomeChecks(web3, sender, valueToTransfer)) {
    return;
  }

  var dt = await DogeToken.deployed();
  await utils.printDogeTokenBalances(dt, sender, receiver);
  // Do transfer  
  console.log("Initiating transfer... ");
  await dt.transfer(receiver, valueToTransfer, {from: sender});     
  console.log("Transfer Done.");
  await utils.printDogeTokenBalances(dt, sender, receiver);
}

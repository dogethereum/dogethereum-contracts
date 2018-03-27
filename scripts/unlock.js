var DogeToken = artifacts.require("./token/DogeToken.sol");
var movetokens = require('./movetokens');


module.exports = async function(callback) {
  movetokens(DogeToken, web3, "unlock", callback)
}


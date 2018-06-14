module.exports = {
  doSomeChecks: async function (web3, sender, valueToTransfer) {
    // Do some checks
    if(!(valueToTransfer > 0)) {
      console.log("Value should be greater than 0");
      return false;
    }
    if(!web3.isConnected()) {
      console.log("Can't connect to ethereum node.");
      return false;
    }
    // TODO: Do this check programatically and print msg 
    try {
      web3.eth.sign(sender, "sample message");
    } catch(err) {
      console.log("Can't use sender private key. Please, make sure the connected ethereum node has sender private key and that account is unlocked.");
      console.log(err);
      return false;
    }
    // Make sure sender has some eth to pay for txs
    var senderEthBalance = await web3.eth.getBalance(sender);     
    if (senderEthBalance.toNumber() == 0) {
      console.log("Sender address has no eth balance, aborting.");
      return false;
    } else {
      console.log("Sender eth balance : " + web3.fromWei(senderEthBalance.toNumber()) + " ETH. Please, make sure that is enough to pay for the tx.");
    }
    return true;
  }
  ,
  printDogeTokenBalances: async function (dt, sender, receiver) {
    // Print sender DogeToken balance before transfer
    var senderDogeTokenBalance = await dt.balanceOf.call(sender);     
    console.log("Sender doge token balance : " + module.exports.dogeToSatoshi(senderDogeTokenBalance.toNumber())  + " doge tokens.");     

    if (receiver) {
      // Print receiver DogeToken balance
      var receiverDogeTokenBalance = await dt.balanceOf.call(receiver);     
      console.log("Receiver doge token balance : " + module.exports.dogeToSatoshi(receiverDogeTokenBalance.toNumber())  + " doge tokens.");               
    }
  }
  ,
  getCliParam: function (argv, i) {
    return argv[6+i];    
  }
  ,
  dogeToSatoshi: function (num) {
    return num / 100000000;
  }  
}  




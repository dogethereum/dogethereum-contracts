var DogeRelay = artifacts.require("./DogeRelay.sol");


contract('DogeRelay', function(accounts) {
  it("Set initial parent", function() {
    var dr;    
    var block333000Hash;
    var block333001Hash;
    var block333001HeaderStr;
    var block333001HeaderBytes;
    return DogeRelay.deployed().then(function(instance) {      
      dr = instance;
      block333000HashReturnValue = "000000000000000008360c20a2ceff91cc8c4f357932377f48659b37bb86c759";
      block333000Hash = "0x" + block333000HashReturnValue;
      block333001HashReturnValue = "000000000000000010e318d0c61da0b84246481d9cc097fda9327fe90b1538c1";
      block333001Hash = "0x" + block333001HashReturnValue;

      // version = 2
      // hashPrevBlock = 0x000000000000000008360c20a2ceff91cc8c4f357932377f48659b37bb86c759
      // hashMerkleRoot = 0xf6f8bc90fd41f626705ac8de7efe7ac723ba02f6d00eab29c6fe36a757779ddd
      // time = 1417792088
      // bits = 0x181b7b74
      // nonce = 796195988
      // blockNumber = 333001
      block333001HeaderStr = "0200000059c786bb379b65487f373279354f8ccc91ffcea2200c36080000000000000000dd9d7757a736fec629ab0ed0f602ba23c77afe7edec85a7026f641fd90bcf8f658ca8154747b1b1894fc742f";
      block333001HeaderStr2 = "0x" + block333001HeaderStr;
      block333001HeaderBytes = parseHexString(block333001HeaderStr);
      return dr.setInitialParent(block333000Hash, 333000, 1, {from: accounts[0]}); 
    }).then(function(result) {
      //assert.equal(result, true, "result should be true");
      return dr.storeBlockHeader(block333001HeaderStr2, {from: accounts[0]}); 
    }).then(function(result) {
      //assert res['output'] == 300000
      return dr.getBlockchainHead.call();
    }).then(function(result) {
      assert.equal(formatHexUint32(result.toString(16)), block333001HashReturnValue, "chain head hash is not the expected one");
      console.log ("111111");
//      return dr.getBlockHeader.call(block333001Hash);
//    }).then(function(resultHeader) {
//      assert.equal(result, block333001HeaderBytes, "chain head header is not the expected one");
//      console.log ("2222");
      return dr.getPrevBlock.call(block333001Hash);
    }).then(function(result) {
      assert.equal(formatHexUint32(result.toString(16)), block333000HashReturnValue, "prev block hash is not the expected one");
      console.log ("3333");
      return dr.getTimestamp.call(block333001Hash);
    }).then(function(result) {
      assert.equal(result.toNumber(), 1417792088, "timestamp is not the expected one");
      console.log ("4444");
      return dr.getBits.call(block333001Hash);
    }).then(function(result) {
      assert.equal(result.toNumber(), 0x181b7b74, "bits is not the expected one");
      console.log ("5555");
    });
  });
});


function parseHexString(str) { 
    var result = [];
    while (str.length >= 2) { 
        result.push(parseInt(str.substring(0, 2), 16));

        str = str.substring(2, str.length);
    }

    return result;
}


function formatHexUint32(str) {
    while (str.length < 64) { 
        str = "0" + str;
    }  
    return str;
}

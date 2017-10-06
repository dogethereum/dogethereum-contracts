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
      block333000Hash = "0x000000000000000008360c20a2ceff91cc8c4f357932377f48659b37bb86c759";
      block333001Hash = "000000000000000010e318d0c61da0b84246481d9cc097fda9327fe90b1538c1"
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
      console.log("block333001HeaderBytes " + block333001HeaderBytes);
      console.log("block333001HeaderBytes " + block333001HeaderBytes[0]);
      console.log("block333001HeaderBytes " + block333001HeaderBytes[79]);

      return dr.setInitialParent(block333000Hash, 333000, 1, {from: accounts[0]}); 
    }).then(function(result) {
      console.log("");
      console.log("setInitialParent result " + JSON.stringify(result, null, "\r"));
      console.log("");
      //assert.equal(result, true, "result should be true");
      return dr.storeBlockHeader(block333001HeaderStr2, {from: accounts[0]}); 
    }).then(function(result) {
      console.log("");
      console.log("storeBlockHeader result " + JSON.stringify(result, null, "\r"));
      console.log("");
      //assert res['output'] == 300000
      return dr.getBlockchainHead.call();
    }).then(function(result) {
      assert.equal(result, block333001Hash, "chain head hash is not the expected one");
      return dr.getBlockHeader.call(block333001Hash);
    }).then(function(resultHeader) {
      assert.equal(result, block333001HeaderBytes, "chain head header is not the expected one");
      return dr.getPrevBlock.call(block333001Hash);
    }).then(function(result) {
      assert.equal(result, block333000Hash, "prev block hash is not the expected one");
      return dr.getTimestamp.call(block333001Hash);
    }).then(function(result) {
      assert.equal(result.toNumber(), 1417792088, "timestamp is not the expected one");
      return dr.getBits.call(block333001Hash);
    }).then(function(result) {
      assert.equal(result, 0x181b7b74, "bits is not the expected one");
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

function syntaxHighlight(json) {
    if (typeof json != 'string') {
         json = JSON.stringify(json, undefined, 2);
    }
    json = json.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    return json.replace(/("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g, function (match) {
        var cls = 'number';
        if (/^"/.test(match)) {
            if (/:$/.test(match)) {
                cls = 'key';
            } else {
                cls = 'string';
            }
        } else if (/true|false/.test(match)) {
            cls = 'boolean';
        } else if (/null/.test(match)) {
            cls = 'null';
        }
        return '<span class="' + cls + '">' + match + '</span>';
    });
}

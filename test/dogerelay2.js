// This is a copy of dogerelay2.js that works with doge blocks
var DogeRelay = artifacts.require("./DogeRelayForTests.sol");


contract('DogeRelay', function(accounts) {
  it("setInitialParent, storeBlockHeader, getBestBlockHash, getBlockHeader, getPrevBlock, m_getTimestamp, m_getBits", function() {
    var dr;    
    // Old bitcoin code
    //var block333000Hash = "0x000000000000000008360c20a2ceff91cc8c4f357932377f48659b37bb86c759";
    //var block333001Hash = "0x000000000000000010e318d0c61da0b84246481d9cc097fda9327fe90b1538c1";
    //// version = 2
    //// hashPrevBlock = 0x000000000000000008360c20a2ceff91cc8c4f357932377f48659b37bb86c759
    //// hashMerkleRoot = 0xf6f8bc90fd41f626705ac8de7efe7ac723ba02f6d00eab29c6fe36a757779ddd
    //// time = 1417792088
    //// bits = 0x181b7b74
    //// nonce = 796195988
    //// blockNumber = 333001
    //var block333001Header = "0x0200000059c786bb379b65487f373279354f8ccc91ffcea2200c36080000000000000000dd9d7757a736fec629ab0ed0f602ba23c77afe7edec85a7026f641fd90bcf8f658ca8154747b1b1894fc742f";
    var block974400Hash = "0xa84956d6535a1be26b77379509594bdb8f186b29c3b00143dcb468015bdd16da";
    var block974401Hash = "0xa10377b456caa4d7a57623ddbcdb4c81e20b4ddaece77396b717fe49488975a4";
    // Block a10377b456caa4d7a57623ddbcdb4c81e20b4ddaece77396b717fe49488975a4 at height 974401:  block: 
    //    hash: a10377b456caa4d7a57623ddbcdb4c81e20b4ddaece77396b717fe49488975a4
    //    version: 6422787 (BIP34, BIP66, BIP65)
    //    previous block: a84956d6535a1be26b77379509594bdb8f186b29c3b00143dcb468015bdd16da
    //    merkle root: 46ee29c6ca582b8aa4e5662a97e15845589765383ed2dbe84411409f82e57eef
    //    time: 1448429048 (2015-11-25T05:24:08Z)
    //    difficulty target (nBits): 453253704
    //    nonce: 0
    var block974401Header = "0x03016200da16dd5b0168b4dc4301b0c3296b188fdb4b59099537776be21b5a53d65649a8ef7ee5829f401144e8dbd23e386597584558e1972a66e5a48a2b58cac629ee46f8455556481a041b0000000001000000010000000000000000000000000000000000000000000000000000000000000000ffffffff6403439e0de4b883e5bda9e7a59ee4bb99e9b1bcfabe6d6d65fdfa97de61e7932a69b3fc70d71fc5fec14639f4d8d92d8da7574acff1c2cd40000000f09f909f4d696e65642062792061696c696e37363232320000000000000000000000000000000000002a0000000168794696000000001976a914aa3750aa18b8a0f3f0590731e1fab934856680cf88acc5d6f6323569d4c55c658997830bce8f904bf4cb74e63cfcc8e1037a5fab03000000000004f529ba9787936a281f792a15d03dc1c6d2a45e25666432bcbe4663ad193a7f15307380ab3ab6f115e796fe4cea3b297b3c22018edad8d3982cf89fe3102265061ae397c9c145539a1de3eddfeff6ba512096542e41498cade2b4986d43d497c74c10c869bc28e301b2d9e7558237b1655f699f93a9635938f58cf750b94d4e9a00000000062900000000000000000000000000000000000000000000000000000000000000463ceed131958d98aee29089d1cf38b9728b224512e51ca3a8b1189d5ed03d0709b68fd6e328528f2a29ec7fb077c834fbf0f14c371fafcfb27444017fbf5b26fdb884bed8ad6a4bded36fc89ed8b05a6c6c0ae1cfd5fe37eb3021b32a1e29042b7a2e142329e7d0d0bffcb5cc338621a576b49d4d32991000b8d4ac793bc1f50c27ad8b8e751d85f7e9dc7a5ff18c817a72cd9976063c6849d1538f6a662d342800000003000000c63abe4881f9c765925fffb15c88cdb861e86a32f4c493a36c3e29c54dc62cf45ba4401d07d6d760e3b84fb0b9222b855c3b7c04a174f17c6e7df07d472d0126fe455556358c011b6017f799";
    return DogeRelay.deployed().then(function(instance) {      
      dr = instance;
      // Old bitcoin code
      //return dr.setInitialParent(block333000Hash, 333000, 1, {from: accounts[0]}); 
      return dr.setInitialParent(block974400Hash, 974400, 1, {from: accounts[0]}); 
    }).then(function(result) {
      //assert.equal(result, true, "result should be true");
      // Old bitcoin code
      //return dr.storeBlockHeader(block333001Header, block333001Hash, {from: accounts[0]}); 
      return dr.storeBlockHeader(block974401Header, block974401Hash, {from: accounts[0]}); 
    }).then(function(result) {
      //assert res['output'] == 300000      
      return dr.getBestBlockHash.call();
    }).then(function(result) {
      // Old bitcoin code
      //assert.equal(formatHexUint32(result.toString(16)), remove0x(block333001Hash), "chain head hash is not the expected one");
      //return dr.getBlockHeader.call(block333001Hash);
      assert.equal(formatHexUint32(result.toString(16)), remove0x(block974401Hash), "chain head hash is not the expected one");
      return dr.getBlockHeader.call(block974401Hash);
    }).then(function(result) {
      // Old bitcoin code
      //assert.equal(result, block333001Header, "chain head header is not the expected one");
      //return dr.getPrevBlockPublic.call(block333001Hash);
      assert.equal(result, block974401Header, "chain head header is not the expected one");
      return dr.getPrevBlockPublic.call(block974401Hash);
    }).then(function(result) {
      // Old bitcoin code
      //assert.equal(formatHexUint32(result.toString(16)), remove0x(block333000Hash), "prev block hash is not the expected one");
      //return dr.m_getTimestampPublic.call(block333001Hash);
      assert.equal(formatHexUint32(result.toString(16)), remove0x(block974400Hash), "prev block hash is not the expected one");
      return dr.m_getTimestampPublic.call(block974401Hash);
    }).then(function(result) {
      // Old bitcoin code
      //assert.equal(result.toNumber(), 1417792088, "timestamp is not the expected one");
      //return dr.m_getBitsPublic.call(block333001Hash);
      assert.equal(result.toNumber(), 1448429048, "timestamp is not the expected one");
      return dr.m_getBitsPublic.call(block974401Hash);
    }).then(function(result) {
      // Old bitcoin code
      //assert.equal(result.toNumber(), 0x181b7b74, "bits is not the expected one");
      assert.equal(result.toNumber(), 0x1B041A48, "bits is not the expected one");
    });
  });
});



function formatHexUint32(str) {
    while (str.length < 64) { 
        str = "0" + str;
    }  
    return str;
}

function remove0x(str) {
    return str.substring(2);
}

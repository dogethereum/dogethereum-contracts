const DogeRelay = artifacts.require("./DogeRelayForTests.sol");
const ScryptCheckerDummy = artifacts.require('./ScryptCheckerDummy.sol');
const utils = require('./utils');


contract('DogeRelay Async', function(accounts) {
  let dogeRelay;
  let scryptChecker;
  before(async () => {
    dogeRelay = await DogeRelay.new(0);
    scryptChecker = await ScryptCheckerDummy.new(false);
    await dogeRelay.setScryptChecker(scryptChecker.address);
  });
  it("Valid async call to DogeRelay", async () => {
    const block974400Hash = "0xa84956d6535a1be26b77379509594bdb8f186b29c3b00143dcb468015bdd16da";
    const block974401Hash = "0xa10377b456caa4d7a57623ddbcdb4c81e20b4ddaece77396b717fe49488975a4";
    const block974401Header = `0x03016200da16dd5b0168b4dc4301b0c3296b188fdb4b59099537776be21b5a53d65649a8ef7ee5829f401144e8dbd23e386597584558e1972a66e5a48a2b58cac629ee46f8455556481a041b0000000001000000010000000000000000000000000000000000000000000000000000000000000000ffffffff6403439e0de4b883e5bda9e7a59ee4bb99e9b1bcfabe6d6d65fdfa97de61e7932a69b3fc70d71fc5fec14639f4d8d92d8da7574acff1c2cd40000000f09f909f4d696e65642062792061696c696e37363232320000000000000000000000000000000000002a0000000168794696000000001976a914aa3750aa18b8a0f3f0590731e1fab934856680cf88acc5d6f6323569d4c55c658997830bce8f904bf4cb74e63cfcc8e1037a5fab03000000000004f529ba9787936a281f792a15d03dc1c6d2a45e25666432bcbe4663ad193a7f15307380ab3ab6f115e796fe4cea3b297b3c22018edad8d3982cf89fe3102265061ae397c9c145539a1de3eddfeff6ba512096542e41498cade2b4986d43d497c74c10c869bc28e301b2d9e7558237b1655f699f93a9635938f58cf750b94d4e9a00000000062900000000000000000000000000000000000000000000000000000000000000463ceed131958d98aee29089d1cf38b9728b224512e51ca3a8b1189d5ed03d0709b68fd6e328528f2a29ec7fb077c834fbf0f14c371fafcfb27444017fbf5b26fdb884bed8ad6a4bded36fc89ed8b05a6c6c0ae1cfd5fe37eb3021b32a1e29042b7a2e142329e7d0d0bffcb5cc338621a576b49d4d32991000b8d4ac793bc1f50c27ad8b8e751d85f7e9dc7a5ff18c817a72cd9976063c6849d1538f6a662d342800000003000000c63abe4881f9c765925fffb15c88cdb861e86a32f4c493a36c3e29c54dc62cf45ba4401d07d6d760e3b84fb0b9222b855c3b7c04a174f17c6e7df07d472d0126fe455556358c011b6017f799`;
    await dogeRelay.setInitialParent(block974400Hash, 974400, 1);
    const blockScryptHash = `0x${utils.calcHeaderPoW(block974401Header)}`;
    await dogeRelay.storeBlockHeader(block974401Header, blockScryptHash, accounts[2]);
    // Verify block not confirmed yet
    const bestBlockHash = await dogeRelay.getBestBlockHash.call();
    assert.equal(utils.formatHexUint32(bestBlockHash.toString(16)), utils.remove0x(block974400Hash), "chain head hash is not the expected one");
    // Send block verification
    await scryptChecker.sendVerification(blockScryptHash);
    // Verify new block has been accepted
    const bestBlockHash2 = await dogeRelay.getBestBlockHash.call();
    assert.equal(utils.formatHexUint32(bestBlockHash2.toString(16)), utils.remove0x(block974401Hash), "chain head hash is not the expected one");
  });
  it("Not valid async call to DogeRelay", async () => {
    const block974401Hash = "0xa10377b456caa4d7a57623ddbcdb4c81e20b4ddaece77396b717fe49488975a4";
    const block974402Hash = "0xb26fc6c25e9097aa7ced3610b45b2f018c5e4730822c9809d5ffb2a860b21b24";
    const block974402Header = `0x03016200a475894849fe17b79673e7ecda4d0be2814cdbbcdd2376a5d7a4ca56b47703a16694d245b05bc4b65a26ba504fedee7f47acf3c354c2f3897964991b784074ee9446555640b1031b0000000001000000010000000000000000000000000000000000000000000000000000000000000000ffffffff6403449e0de4b883e5bda9e7a59ee4bb99e9b1bcfabe6d6d84117b09e5d99fc04280af2d78bb36915e1b196c65d454aec3b0fb88b8e1ec6240000000f09f909f4d696e65642062792077616e67636875616e776569000000000000000000000000000000001b0100000148e01995000000001976a914aa3750aa18b8a0f3f0590731e1fab934856680cf88acf2770637d9c2b6599fc2bc94a4b9c2a3c8589f2fd62e4a0459bc13f33aa401000000000005462f31ec45cdd06c1098d74e311d2182eb1320694ac39c8b13de927800959eb0c586e12adb95b25281c4fd377bda5f5b4dc4477dd237faf7c68aa7ff690cbc47c58a8ef40c56afe6262c57ccbc88f368caceb048b674a89146794434e3796f9173d35744c56a580399985ea21897a1f4ee112906634bbb7ee00e3652ff2351e1e8550037fffb2db59f11dc1d492d6311e2376abaf895acaa6d5e391259491e2d00000000062900000000000000000000000000000000000000000000000000000000000000463ceed131958d98aee29089d1cf38b9728b224512e51ca3a8b1189d5ed03d0709b68fd6e328528f2a29ec7fb077c834fbf0f14c371fafcfb27444017fbf5b26fdb884bed8ad6a4bded36fc89ed8b05a6c6c0ae1cfd5fe37eb3021b32a1e29042b7a2e142329e7d0d0bffcb5cc338621a576b49d4d32991000b8d4ac793bc1f5258991030d537050ab2d4b302f1966c3e1d25816ba5c6701710cc2e32d35cf9e280000000300000071fad47a6bcb4f483da2562d7e1afeb03bfa07a4540365fbf2ef3db5be41598052989d551f777b8ba0f13067f45d03627552e878432735738278eb500864da5594465556358c011bff0c2f00`;
    const block974402ScryptHash = `0x${utils.calcHeaderPoW(block974402Header)}`;
    const block974403Hash = "0x163b557f1020e18c8fddc25327ec164374e36466aad4a5741221094c9a14d208";
    const block974403Header = `0x03016200241bb260a8b2ffd509982c8230475e8c012f5bb41036ed7caa97905ec2c66fb25e2f04306e21065b956b5726e1f1dfed1a468b7309dff926628c53f453c53142b14655564c6e041b0000000001000000010000000000000000000000000000000000000000000000000000000000000000ffffffff6403449e0de4b883e5bda9e7a59ee4bb99e9b1bcfabe6d6d2eb40132424f2d742e503a6052788225449011e7ca46d5ce3be2189aab6f40f940000000f09f909f4d696e6564206279206c7463303031000000000000000000000000000000000000000000003de7050001c8abbe95000000001976a914aa3750aa18b8a0f3f0590731e1fab934856680cf88acc92c61360f08ad87f772eb16bdd893a49bf2f02bb4a3bcb8e3605b9046bb0200000000000531c3275dc3dcb07bcf550a77d5c63b29959d034536ab5afeac74c36c37727dcd5752dd9effcbda9c1e5ddc17aa1f1a984192d834b8ff5a1a60e9efd55bf94f1532391099740d20947b24a3556a61602d43e8eabc8ebdba8152459c3a3f24b5c5276a9eed0dbd8b253cef989c0b3a91ed6c2cfba17488646287cb1a8b31d20a7e808778fa84ff3413c05b7debab62b8385fa7625d5c3db31775911b54f86ddbf000000000062900000000000000000000000000000000000000000000000000000000000000463ceed131958d98aee29089d1cf38b9728b224512e51ca3a8b1189d5ed03d0709b68fd6e328528f2a29ec7fb077c834fbf0f14c371fafcfb27444017fbf5b26fdb884bed8ad6a4bded36fc89ed8b05a6c6c0ae1cfd5fe37eb3021b32a1e29042b7a2e142329e7d0d0bffcb5cc338621a576b49d4d32991000b8d4ac793bc1f50800d93cbb266b6d9cf068dea7fdb153f648f673583e0c196985ab21d576e86c280000000300000071fad47a6bcb4f483da2562d7e1afeb03bfa07a4540365fbf2ef3db5be41598057f99a71e88ddc60bdd708d004c740b816a55a924759e4de63649d21546584c0e9465556358c011b12ebae8e`;
    const block974403ScryptHash = `0x${utils.calcHeaderPoW(block974403Header)}`;
    // Check last block confirmed
    const bestBlockHash = await dogeRelay.getBestBlockHash.call();
    assert.equal(utils.formatHexUint32(bestBlockHash.toString(16)), utils.remove0x(block974401Hash), "chain head hash is not the expected one");
    // Send both blocks
    await dogeRelay.storeBlockHeader(block974402Header, block974402ScryptHash, accounts[2]);
    await dogeRelay.storeBlockHeader(block974403Header, block974403ScryptHash, accounts[2]);
    // Try to verify block second block first
    await scryptChecker.sendVerification(block974403ScryptHash);
    // Best block should not change
    // Out of order blocks are not accepted
    const bestBlockHash2 = await dogeRelay.getBestBlockHash.call();
    assert.equal(utils.formatHexUint32(bestBlockHash2.toString(16)), utils.remove0x(block974401Hash), "chain head hash is not the expected one");
    // Send first block verification
    await scryptChecker.sendVerification(block974402ScryptHash);
    const bestBlockHash3 = await dogeRelay.getBestBlockHash.call();
    assert.equal(utils.formatHexUint32(bestBlockHash3.toString(16)), utils.remove0x(block974402Hash), "chain head hash is not the expected one");
    // Now verify second block
    await scryptChecker.sendVerification(block974403ScryptHash);
    const bestBlockHash4 = await dogeRelay.getBestBlockHash.call();
    assert.equal(utils.formatHexUint32(bestBlockHash4.toString(16)), utils.remove0x(block974403Hash), "chain head hash is not the expected one");
  });
});

const utils = require('../test/utils.js');
const DogeRelay = artifacts.require('DogeRelay.sol');
const DogeToken = artifacts.require('DogeToken.sol');
const ClaimManager = artifacts.require('ClaimManager.sol');

function mineBlock(provider) {
  return provider.send({ jsonrpc: '2.0', method: 'evm_mine', params: [], id: 0 });
}

function mineBlocks(provider, blocks) {
  let seq = Promise.resolve();
  for (let i=0; i<20; ++i) {
    seq = seq.then(() => mineBlock(provider));
  }
  return seq;
}

module.exports = async (callback) => {
  try {
    const dogeRelay = await DogeRelay.deployed();
    const claimManager = await ClaimManager.deployed();

    const dogeRelayEvents = dogeRelay.allEvents();
    const claimManagerEvents = claimManager.allEvents();

    const eventsFormatter = (eventEntry) => {
      // console.log(`xxxxxxxxx ${eventEntry.address} xxxx ${dogeRelay.address}`);
      if (eventEntry.address === DogeRelay.address) {
        return dogeRelayEvents.formatter(eventEntry);
      } else if (eventEntry.address === ClaimManager.address) {
        return claimManagerEvents.formatter(eventEntry);
      }
      return eventEntry;
    }

    const block974400Hash = "0xa84956d6535a1be26b77379509594bdb8f186b29c3b00143dcb468015bdd16da";

    let res;
    res = await dogeRelay.setInitialParent(block974400Hash, 974400, 1);

    //console.log(`--1--${JSON.stringify(res, null, '  ')}`);

    res = await claimManager.makeDeposit({ value: web3.toWei(1, 'gwei') });
    res.logs = res.receipt.logs.map(eventsFormatter);

    //console.log(`--2--${JSON.stringify(res, null, '  ')}`);

    const block974401Hash = '0xa10377b456caa4d7a57623ddbcdb4c81e20b4ddaece77396b717fe49488975a4';
    const block974401Header =  `0x03016200da16dd5b0168b4dc4301b0c3296b188fdb4b59099537776be21b5a53d65649a8ef7ee5829f401144e8dbd23e386597584558e1972a66e5a48a2b58cac629ee46f8455556481a041b0000000001000000010000000000000000000000000000000000000000000000000000000000000000ffffffff6403439e0de4b883e5bda9e7a59ee4bb99e9b1bcfabe6d6d65fdfa97de61e7932a69b3fc70d71fc5fec14639f4d8d92d8da7574acff1c2cd40000000f09f909f4d696e65642062792061696c696e37363232320000000000000000000000000000000000002a0000000168794696000000001976a914aa3750aa18b8a0f3f0590731e1fab934856680cf88acc5d6f6323569d4c55c658997830bce8f904bf4cb74e63cfcc8e1037a5fab03000000000004f529ba9787936a281f792a15d03dc1c6d2a45e25666432bcbe4663ad193a7f15307380ab3ab6f115e796fe4cea3b297b3c22018edad8d3982cf89fe3102265061ae397c9c145539a1de3eddfeff6ba512096542e41498cade2b4986d43d497c74c10c869bc28e301b2d9e7558237b1655f699f93a9635938f58cf750b94d4e9a00000000062900000000000000000000000000000000000000000000000000000000000000463ceed131958d98aee29089d1cf38b9728b224512e51ca3a8b1189d5ed03d0709b68fd6e328528f2a29ec7fb077c834fbf0f14c371fafcfb27444017fbf5b26fdb884bed8ad6a4bded36fc89ed8b05a6c6c0ae1cfd5fe37eb3021b32a1e29042b7a2e142329e7d0d0bffcb5cc338621a576b49d4d32991000b8d4ac793bc1f50c27ad8b8e751d85f7e9dc7a5ff18c817a72cd9976063c6849d1538f6a662d342800000003000000c63abe4881f9c765925fffb15c88cdb861e86a32f4c493a36c3e29c54dc62cf45ba4401d07d6d760e3b84fb0b9222b855c3b7c04a174f17c6e7df07d472d0126fe455556358c011b6017f799`;
    const block974401ScryptHash = `0x${utils.calcHeaderPoW(block974401Header)}`;
    res = await dogeRelay.storeBlockHeader(block974401Header, block974401ScryptHash, web3.eth.accounts[0]);

    res.logs = res.receipt.logs.map(eventsFormatter);

    //console.log(`--3--${JSON.stringify(res, null, '  ')}`);
    let claimID;
    claimID = parseInt(res.logs[1].args.claimID);

    //console.log(`ClaimID: ${claimID}`);

    await mineBlocks(DogeRelay.currentProvider, 20);

    res = await claimManager.runNextVerificationGame(claimID);

    res.logs = res.receipt.logs.map(eventsFormatter);

    //console.log(`--4--${JSON.stringify(res, null, '  ')}`);

    res = await claimManager.checkClaimSuccessful(claimID);

    res.logs = res.receipt.logs.map(eventsFormatter);

    //console.log(`--5--${JSON.stringify(res, null, '  ')}`);

    const block974402Hash = '0xb26fc6c25e9097aa7ced3610b45b2f018c5e4730822c9809d5ffb2a860b21b24';
    const block974402Header = `0x03016200a475894849fe17b79673e7ecda4d0be2814cdbbcdd2376a5d7a4ca56b47703a16694d245b05bc4b65a26ba504fedee7f47acf3c354c2f3897964991b784074ee9446555640b1031b0000000001000000010000000000000000000000000000000000000000000000000000000000000000ffffffff6403449e0de4b883e5bda9e7a59ee4bb99e9b1bcfabe6d6d84117b09e5d99fc04280af2d78bb36915e1b196c65d454aec3b0fb88b8e1ec6240000000f09f909f4d696e65642062792077616e67636875616e776569000000000000000000000000000000001b0100000148e01995000000001976a914aa3750aa18b8a0f3f0590731e1fab934856680cf88acf2770637d9c2b6599fc2bc94a4b9c2a3c8589f2fd62e4a0459bc13f33aa401000000000005462f31ec45cdd06c1098d74e311d2182eb1320694ac39c8b13de927800959eb0c586e12adb95b25281c4fd377bda5f5b4dc4477dd237faf7c68aa7ff690cbc47c58a8ef40c56afe6262c57ccbc88f368caceb048b674a89146794434e3796f9173d35744c56a580399985ea21897a1f4ee112906634bbb7ee00e3652ff2351e1e8550037fffb2db59f11dc1d492d6311e2376abaf895acaa6d5e391259491e2d00000000062900000000000000000000000000000000000000000000000000000000000000463ceed131958d98aee29089d1cf38b9728b224512e51ca3a8b1189d5ed03d0709b68fd6e328528f2a29ec7fb077c834fbf0f14c371fafcfb27444017fbf5b26fdb884bed8ad6a4bded36fc89ed8b05a6c6c0ae1cfd5fe37eb3021b32a1e29042b7a2e142329e7d0d0bffcb5cc338621a576b49d4d32991000b8d4ac793bc1f5258991030d537050ab2d4b302f1966c3e1d25816ba5c6701710cc2e32d35cf9e280000000300000071fad47a6bcb4f483da2562d7e1afeb03bfa07a4540365fbf2ef3db5be41598052989d551f777b8ba0f13067f45d03627552e878432735738278eb500864da5594465556358c011bff0c2f00`;
    const block974402ScryptHash = `0x${utils.calcHeaderPoW(block974402Header)}`;
    res = await dogeRelay.storeBlockHeader(block974402Header, block974402ScryptHash, web3.eth.accounts[0]);

    res.logs = res.receipt.logs.map(eventsFormatter);

    //console.log(`--6--${JSON.stringify(res, null, '  ')}`);

    claimID = parseInt(res.logs[1].args.claimID);

    await mineBlocks(DogeRelay.currentProvider, 20);

    res = await claimManager.runNextVerificationGame(claimID);

    res.logs = res.receipt.logs.map(eventsFormatter);

    res = await claimManager.checkClaimSuccessful(claimID);

    res.logs = res.receipt.logs.map(eventsFormatter);

    //console.log(`--7--${JSON.stringify(res, null, '  ')}`);

    console.log("Transaction successful!");
    callback();
  } catch(err) {
    // There was an error! Handle it.
    callback(err);
  }
}

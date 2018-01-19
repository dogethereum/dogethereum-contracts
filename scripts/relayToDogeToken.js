/**
 * Script to verify correct deployment to ropsten
 */

const fs = require('fs');
const HDWalletProvider = require('truffle-hdwallet-provider');
const Contract = require('truffle-contract');
const utils = require('../test/utils');
const config = require('../config');

async function runTest() {
  try {
    const provider = new HDWalletProvider(config.wallet.seed, config.rpcpath);

    const DogeRelayJson = JSON.parse(fs.readFileSync('build/contracts/DogeRelay.json'));
    const DogeRelay = Contract(DogeRelayJson);
    // DogeRelay.setNetwork('ropsten');
    DogeRelay.setProvider(provider);

    const DogeTokenJson = JSON.parse(fs.readFileSync('build/contracts/DogeToken.json'));
    const DogeToken = Contract(DogeTokenJson);
    // DogeToken.setNetwork('ropsten');
    DogeToken.setProvider(provider);

    console.log(`Address: ${provider.address}`);

    const dogeRelay = await DogeRelay.deployed();
    const dogeToken = await DogeToken.deployed();

    //const bestBlockHash = await dogeRelay.getBestBlockHash.call();

    //console.log(`Best block hash: 0x${bestBlockHash.toString(16)}`);


    const senderAddress = '0xcee8908546b4e94debc0f6acc9cd3462ee80dc49';

    const blockHeight = await dogeRelay.getBestBlockHeight.call();

    if (blockHeight.toNumber() === 0) {
      // Initialize contract
      await utils.bulkStore10From974401(dogeRelay, senderAddress);
    } else {
      console.log(`BlockHeight: ${blockHeight}`);
    }

    const blockHash = '0xb26fc6c25e9097aa7ced3610b45b2f018c5e4730822c9809d5ffb2a860b21b24';
    const txIndex = 2; // Third tx in the block
    const txHash = '718add98dca8f54288b244dde3b0e797e8fe541477a08ef4b570ea2b07dccd3f';
    const txData = `0x01000000063bdae6e5c8f64d72ebe4003eafe6d91249cab1c1bee36314d537e11adc3f141d000000006b483045022100e4c4f3d36eac2f4a517298cf76f759f01d153c2e5aa87ad3a209cb24b752663b02202a3b55d99d81718a84f204017698b31a59bd00a86ab32c4ce8df76004f52ae51012102a301f6ade783ed61d626f1621b85500a9edbc0cae8060c2a95899ae839e2c13dffffffff483126afc42fbeb4983fd27b77b8748c78798d8563323f48053a92b313716056000000006a47304402207b367dd68c6f6f8b354b010471d241762e03dc640ca07804f31fafd57d4cafd302200e377decdaf301cd04784d1ebd349ff0d1783522a425b8fcd442560fd15e9531012102a301f6ade783ed61d626f1621b85500a9edbc0cae8060c2a95899ae839e2c13dffffffff1418d9fcd1eb3444b1b8465b883dc9415aa7da615f6cc34b2e11b5a7d4fd3066000000006a47304402204d9079ca627a98dcccd1b10f0b3d0d9a709298930241b477440b9506f6fc54f302201a9b3477d9b1e3524a7f81d0aa719bd87a35e30eec6c899e7325688b6cd14390012102a301f6ade783ed61d626f1621b85500a9edbc0cae8060c2a95899ae839e2c13dffffffffeca8cc769cc3fa69f09b9037526838c7dddf6b0a8ced1f75459d4cfb8e48d550010000006a47304402201efdc9d5075205e1a178a0e0aaf8361e652a54c1f439df171eeb4b0e707ab63f022056421c5a89363f8cb55906b2e718352bf5ced9bfaca637c3e00eea6c8ac2038a012102a301f6ade783ed61d626f1621b85500a9edbc0cae8060c2a95899ae839e2c13dffffffffa9b4da7de89b6223eb750ffbcc89bda025493f3f3fb5c3f975215b74d6809932000000006a473044022028ecf6dbfc9d6ffc16684ecb8ae57855cccc2becf6e7b29bf066534f557f3155022003ec603c3b55eb377f3d13f0aaefd96e9edc918084f46e5ca1b5aad66d509994012102a301f6ade783ed61d626f1621b85500a9edbc0cae8060c2a95899ae839e2c13dffffffff72a248edd78124a59a7b86c8ba769f0ac87d7c80fcf330afdce3a4c55adc1239010000006a473044022044a1df03aed5bbec8e6f9fe4f9dadcd50ba3acd0f9ae059862096d6984c6d5430220185d7517e6adedb67dbd04fc12fb1f6dd12ee49739b730537d91a1c2363e41ac012102a301f6ade783ed61d626f1621b85500a9edbc0cae8060c2a95899ae839e2c13dffffffff024ffb0ee9d20000001976a9144d905b4b815d483cdfabcd292c6f86509d0fad8288acb18eb768020000001976a914b4c03c57520462083b8c19d676b8fdc3d374c8c088ac00000000`;

    const hashes = [
      '5c090206d5ccc1827ca7cb723b9f706a1ed8c9bb17d9dc0c7188c2ee10a7501c',
      'af12afe762daf75815db0097e16445dbba45ce9140f3da37b86f00b45bd627b2',
      '718add98dca8f54288b244dde3b0e797e8fe541477a08ef4b570ea2b07dccd3f',
      '0c1c11cc899dfa6f01477e82969c5b2c07f934445bbf116c15f6d06541bc52da',
      '0c6fcfd484ff722d3c512bf38c38904fb75fefdd16d187827887259573d4da6d',
      'd85837d895dc1f38104366a7c2dfe6290f7175d2a69240ebe8bb36ffc52ed4d3',
      '755b9f137575fe9a8dfc984673f62e80b2eba3b3b8f8000a799a3f14730dbe72',
      '42cf9e7db40d99edd323d786d56f6be8159a7e7be458418917b02b2b3be51684',
      'cc8c0f43a1e2100c5b9841495ed1f123f2e3b0a2411c43234526347609034588',
      '89d95e9f1d627bb810ea6799b6f7bd79776bc60a3d61cb40f537c3cba9d53865',
      '271f317be9122894e6aef9491a877418ebb82f8de53615d3de8e8403bdbbe38b',
      '3aaed4666225d73f4fd40ccf0602cbc3555c0969ba5f909e56e11da14ddb44b9',
      '2f28d3ff74af7e5621ba8947dc20792cc5e082283f00cd4fb8475b18f0531c3c',
      '6c9065e5f18e498806e3a483af4a0cb928886f6ba0a97b1134dade772351ff46',
      '73307cd2527f6fbc736bfc7a6eb692a283bc647aab650863a8ca8ea7a60c4fa0',
      '649ca5456c1cca1c5cf2c17a527208957a75e42b22e651c5e8f43e8647e01b2f',
      '25a51303b4b9e648bb1fb66b4aff5e2c46e4cd99646bda975f2347e709acabdb',
      'f88050416d4efbd9940d582f67f5cda3db4414dd35db269ab72d8a7981a74605',
      'ff96cf9beaed0c31a633c3c0c87f4e040bd4f042998c787ace9c07245ad7dee7',
      'b625dc14e0c402f6d6e3c9beac35fb5aaa5db83c04ef7dfdd508d29e49aacf64',
      'f8b195ba046226b4ca040a482e7a823bfcb2d61d9733f5689d0d99c8d6795076',
      '877973b213eb921161777b96fdd50f9bc4701b13de8842e7c940b9daa3e91baa',
      '076a27faec1d71499c7946c974073e3a9d27fbdaf2a491df960669a122090b29'
    ];

    const siblings = utils.makeMerkleProof(hashes, txIndex);
    for(var i = 0; i < siblings.length; i++) {
      siblings[i] = "0x" + siblings[i];
    }

    console.log(`DogeToken address: ${dogeToken.address}`);

    await dogeRelay.relayTx(txData, txIndex, siblings, blockHash, dogeToken.address, { from: senderAddress });

    const address = '0x30d90d1dbf03aa127d58e6af83ca1da9e748c98d';
    const value = 'd2e90efb4f';
    const balance = await dogeToken.balanceOf(address);
    if (balance.toString(16) != value) {
      console.log(`DogeToken's ${address} balance ${balance.toString(16)} is not the expected one ${value}`);
    } else {
      console.log(`DogeToken's ${address} balance is correct`);
    }
  } catch (err) {
    console.log(`Error: ${err} - ${err.stack}`);
  }
}

runTest();

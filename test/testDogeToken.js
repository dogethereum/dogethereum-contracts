// var DogeRelay = artifacts.require("./DogeRelayForTests.sol");
var DogeToken = artifacts.require("./token/DogeTokenForTests.sol");
var utils = require('./utils');


contract('testDogeToken', function(accounts) {
  let dogeToken;
  const trustedDogeEthPriceOracle = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const dogethereumRecipient = '0x4d905b4b815d483cdfabcd292c6f86509d0fad82';
  before(async () => {
    dogeToken = await DogeToken.new(accounts[0], trustedDogeEthPriceOracle, dogethereumRecipient);
  });
  it("Test parsing transaction", async () => {
    const txHash = '0x718add98dca8f54288b244dde3b0e797e8fe541477a08ef4b570ea2b07dccd3f';
    const txData = `0x01000000063bdae6e5c8f64d72ebe4003eafe6d91249cab1c1bee36314d537e11adc3f141d000000006b483045022100e4c4f3d36eac2f4a517298cf76f759f01d153c2e5aa87ad3a209cb24b752663b02202a3b55d99d81718a84f204017698b31a59bd00a86ab32c4ce8df76004f52ae51012102a301f6ade783ed61d626f1621b85500a9edbc0cae8060c2a95899ae839e2c13dffffffff483126afc42fbeb4983fd27b77b8748c78798d8563323f48053a92b313716056000000006a47304402207b367dd68c6f6f8b354b010471d241762e03dc640ca07804f31fafd57d4cafd302200e377decdaf301cd04784d1ebd349ff0d1783522a425b8fcd442560fd15e9531012102a301f6ade783ed61d626f1621b85500a9edbc0cae8060c2a95899ae839e2c13dffffffff1418d9fcd1eb3444b1b8465b883dc9415aa7da615f6cc34b2e11b5a7d4fd3066000000006a47304402204d9079ca627a98dcccd1b10f0b3d0d9a709298930241b477440b9506f6fc54f302201a9b3477d9b1e3524a7f81d0aa719bd87a35e30eec6c899e7325688b6cd14390012102a301f6ade783ed61d626f1621b85500a9edbc0cae8060c2a95899ae839e2c13dffffffffeca8cc769cc3fa69f09b9037526838c7dddf6b0a8ced1f75459d4cfb8e48d550010000006a47304402201efdc9d5075205e1a178a0e0aaf8361e652a54c1f439df171eeb4b0e707ab63f022056421c5a89363f8cb55906b2e718352bf5ced9bfaca637c3e00eea6c8ac2038a012102a301f6ade783ed61d626f1621b85500a9edbc0cae8060c2a95899ae839e2c13dffffffffa9b4da7de89b6223eb750ffbcc89bda025493f3f3fb5c3f975215b74d6809932000000006a473044022028ecf6dbfc9d6ffc16684ecb8ae57855cccc2becf6e7b29bf066534f557f3155022003ec603c3b55eb377f3d13f0aaefd96e9edc918084f46e5ca1b5aad66d509994012102a301f6ade783ed61d626f1621b85500a9edbc0cae8060c2a95899ae839e2c13dffffffff72a248edd78124a59a7b86c8ba769f0ac87d7c80fcf330afdce3a4c55adc1239010000006a473044022044a1df03aed5bbec8e6f9fe4f9dadcd50ba3acd0f9ae059862096d6984c6d5430220185d7517e6adedb67dbd04fc12fb1f6dd12ee49739b730537d91a1c2363e41ac012102a301f6ade783ed61d626f1621b85500a9edbc0cae8060c2a95899ae839e2c13dffffffff024ffb0ee9d20000001976a9144d905b4b815d483cdfabcd292c6f86509d0fad8288acb18eb768020000001976a914b4c03c57520462083b8c19d676b8fdc3d374c8c088ac00000000`;

    const address = '0x30d90d1dbf03aa127d58e6af83ca1da9e748c98d';
    const value = 'd2e90efb4f';

    await dogeToken.processTransaction(txData, txHash);

    const balance = await dogeToken.balanceOf(address);
    const utxo = await dogeToken.utxos(0);

    assert.equal(balance.toString(16), value, `DogeToken's ${address} balance is not the expected one`);
    assert.equal(utxo[0], 905853205327, `Utxo's value is not the expected one`);
    assert.equal(utxo[1].toString(16), utils.remove0x(txHash), `Utxo's value is not the expected one`);
    assert.equal(utxo[2], 0, `Utxo's index is not the expected one`);
  });
});

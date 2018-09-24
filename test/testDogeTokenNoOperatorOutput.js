const utils = require('./utils');
const bitcoin = require('bitcoinjs-lib');
const DogeToken = artifacts.require("./token/DogeTokenForTests.sol");

contract('testDogeTokenNoOperatorOutput', function(accounts) {
  const trustedDogeEthPriceOracle = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const trustedRelayerContract = accounts[0]; // Tell DogeToken to trust accounts[0] as it would be the relayer contract
  const collateralRatio = 2;

  const DOGECOIN = {
    messagePrefix: '\x19Dogecoin Signed Message:\n',
    bip32: {
      public: 0x02facafd,
      private: 0x02fac398
    },
    pubKeyHash: 0x1e,
    scriptHash: 0x16,
    wif: 0x9e
  }
  it("Accept unlock transaction without output for operator", async () => {
    const keyPair = bitcoin.ECPair.fromWIF('QSRUX7i1WVzFW6vx3i4Qj8iPPQ1tRcuPanMun8BKf8ySc8LsUuKx', DOGECOIN);
    const keyPair2 = bitcoin.ECPair.fromWIF('QULAK58teBn1Xi4eGo4fKea5oQDPMK4vcnmnivqzgvCPagsWHiyf', DOGECOIN);

    const operatorDogeAddress2 = bitcoin.payments.p2pkh({ pubkey: keyPair2.publicKey, network: DOGECOIN }).address;

    const operatorPublicKeyHash = `0x${bitcoin.crypto.ripemd160(bitcoin.crypto.sha256(keyPair.publicKey)).toString('hex')}`;

    const txb = new bitcoin.TransactionBuilder(DOGECOIN);
    txb.setVersion(1);
    txb.addInput('edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67', 0);
    txb.addOutput(operatorDogeAddress2, 1000000);
    txb.sign(0, keyPair);

    const tx = txb.build();
    const txData = `0x${tx.toHex()}`;
    const txHash = `0x${tx.getId()}`;

    const dogeToken = await DogeToken.new(trustedRelayerContract, trustedDogeEthPriceOracle, collateralRatio);

    const operatorEthAddress = accounts[3];

    await dogeToken.addOperatorSimple(operatorPublicKeyHash, operatorEthAddress);

    const superblockSubmitterAddress = accounts[4];
    await dogeToken.processTransaction(txData, txHash, operatorPublicKeyHash, superblockSubmitterAddress);
  });
});

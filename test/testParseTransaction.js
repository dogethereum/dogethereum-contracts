const utils = require('./utils');
const DogeMessageLibraryForTests = artifacts.require('DogeMessageLibraryForTests');

contract('testParseTransaction', (accounts) => {
  let dogeMessageLibraryForTests;
  const keys = [
    'QSRUX7i1WVzFW6vx3i4Qj8iPPQ1tRcuPanMun8BKf8ySc8LsUuKx',
    'QULAK58teBn1Xi4eGo4fKea5oQDPMK4vcnmnivqzgvCPagsWHiyf',
  ].map(utils.dogeKeyPairFromWIF);
  before(async () => {
    dogeMessageLibraryForTests = await DogeMessageLibraryForTests.deployed();
  });
  it('Parse simple transation', async () => {
    const tx = utils.buildDogeTransaction({
      signer: keys[1],
      inputs: [['edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67', 0]],
      outputs: [
        [utils.dogeAddressFromKeyPair(keys[1]), 1000001],
        [utils.dogeAddressFromKeyPair(keys[0]), 1000002],
      ],
    });
    const operatorPublicKeyHash = utils.publicKeyHashFromKeyPair(keys[0]);
    const txData = `0x${tx.toHex()}`;
    const txHash = `0x${tx.getId()}`;

    const { 0: amount, 1: inputPubKeyHash, 2: inputEthAddress, 3: outputIndex } = await dogeMessageLibraryForTests.parseTransaction(txData, operatorPublicKeyHash);
    assert.equal(amount, 1000002, 'Amount deposited to operator');
    assert.equal(inputPubKeyHash, utils.publicKeyHashFromKeyPair(keys[1]), 'Sender public key hash');
    assert.equal(inputEthAddress.toLowerCase(), utils.ethAddressFromKeyPair(keys[1]), 'Sender ethereum address');
    assert.equal(outputIndex, 1, 'Operator is second output');
  });
  it('Parse transation without operator output', async () => {
    const tx = utils.buildDogeTransaction({
      signer: keys[1],
      inputs: [['edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67', 0]],
      outputs: [
        [utils.dogeAddressFromKeyPair(keys[0]), 1000002],
      ],
    });
    const operatorPublicKeyHash = utils.publicKeyHashFromKeyPair(keys[1]);
    const txData = `0x${tx.toHex()}`;
    const txHash = `0x${tx.getId()}`;

    const { 0: amount, 1: inputPubKeyHash, 2: inputEthAddress, 3: outputIndex } = await dogeMessageLibraryForTests.parseTransaction(txData, operatorPublicKeyHash);
    assert.equal(amount, 0, 'Amount deposited to operator');
    assert.equal(inputPubKeyHash, utils.publicKeyHashFromKeyPair(keys[1]), 'Sender public key hash');
    assert.equal(inputEthAddress.toLowerCase(), utils.ethAddressFromKeyPair(keys[1]), 'Sender ethereum address');
    assert.equal(outputIndex, 0, 'Operator has no output');
  });
  it('Parse transation without OP_RETURN', async () => {
    const tx = utils.buildDogeTransaction({
      signer: keys[1],
      inputs: [['edbbd164551c8961cf5f7f4b22d7a299dd418758b611b84c23770219e427df67', 0]],
      outputs: [
        [utils.dogeAddressFromKeyPair(keys[1]), 1000001],
        [utils.dogeAddressFromKeyPair(keys[0]), 1000002],
        ['OP_RETURN', 0, Buffer.from(accounts[3].slice(2), 'hex')],
      ],
    });
    const operatorPublicKeyHash = utils.publicKeyHashFromKeyPair(keys[0]);
    const txData = `0x${tx.toHex()}`;
    const txHash = `0x${tx.getId()}`;

    const { 0: amount, 1: inputPubKeyHash, 2: inputEthAddress, 3: outputIndex } = await dogeMessageLibraryForTests.parseTransaction(txData, operatorPublicKeyHash);
    assert.equal(amount, 1000002, 'Amount deposited to operator');
    assert.equal(inputPubKeyHash, utils.publicKeyHashFromKeyPair(keys[1]), 'Sender public key hash');
    assert.equal(inputEthAddress, accounts[3], 'Sender ethereum address');
    assert.equal(outputIndex, 1, 'Operator is second output');
  });
});

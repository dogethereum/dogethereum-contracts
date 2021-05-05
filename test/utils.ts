const fs = require('fs');
const readline = require('readline');
const btcProof = require('bitcoin-proof');
const scryptsy = require('scryptsy');
const sha256 = require('js-sha256').sha256;
const keccak256 = require('js-sha3').keccak256;
const bitcoreLib = require('bitcore-lib');
const ECDSA = bitcoreLib.crypto.ECDSA;
const bitcoreMessage = require('bitcore-message');
const bitcoin = require('bitcoinjs-lib');
const BN = require('bn.js');


const OPTIONS_DOGE_REGTEST = {
  DURATION: 600,           // 10 minute
  DELAY: 60,               // 1 minute
  TIMEOUT: 15,             // 15 seconds
  CONFIRMATIONS: 1,        // Superblocks required to confirm semi approved superblock
  REWARD: 3                // Monetary reward for opponent in case battle is lost
};

const DOGE_MAINNET = 0;
const DOGE_TESTNET = 1;
const DOGE_REGTEST = 2;

const DEPOSITS = {
    MIN_REWARD: 400000,
    SUPERBLOCK_COST: 440000,
    CHALLENGE_COST: 34000,
    MIN_PROPOSAL_DEPOSIT: 434000,
    MIN_CHALLENGE_DEPOSIT: 840000,
    QUERY_MERKLE_COST: 88000,
    QUERY_HEADER_COST: 102000,
    RESPOND_MERKLE_COST: 378000, // TODO: measure this with 60 hashes
    RESPOND_HEADER_COST: 40000,
    REQUEST_SCRYPT_COST: 80000,
    VERIFY_SUPERBLOCK_COST: 220000
};

// Parse a data file returns a struct with headers and hashes
async function parseDataFile(filename) {
  const headers = [];
  const hashes = [];
  return new Promise((resolve, reject) => {
    const lineReader = readline.createInterface({
      input: fs.createReadStream(filename)
    });
    lineReader.on('line', function (line) {
      const [header, hash] = line.split("|");
      headers.push(header);
      hashes.push(hash);
    });
    lineReader.on('close', function () {
      resolve({ headers, hashes });
    });
  });
};

// Calculates the merkle root from an array of hashes
// The hashes are expected to be 32 bytes in hexadecimal
function makeMerkle(hashes) {
  if (hashes.length == 0) {
    throw new Error('Cannot compute merkle tree of an empty array');
  }

  return `0x${btcProof.getMerkleRoot(
    hashes.map(x => formatHexUint32(remove0x(x)) )
  )}`;
}

// Format an array of hashes to bytes array
// Hashes are expected to be 32 bytes in hexadecimal
function hashesToData(hashes) {
  let result = '';
  hashes.forEach(hash => {
    result += `${formatHexUint32(remove0x(hash))}`;
  });
  return `0x${result}`;
}

// Calculates the Dogecoin Scrypt hash from block header
// Block header is expected to be in hexadecimal
// Return the concatenated Scrypt hash and block header
function headerToData(blockHeader) {
  const scryptHash = formatHexUint32(calcHeaderPoW(blockHeader));
  return `0x${scryptHash}${blockHeader}`;
}

// Calculates the double sha256 of a block header
// Block header is expected to be in hexadecimal
function calcBlockSha256Hash(blockHeader) {
  const headerBin = fromHex(blockHeader).slice(0, 80);
  return `0x${Buffer.from(sha256.array(sha256.arrayBuffer(headerBin))).reverse().toString('hex')}`;
}

// Get timestamp from dogecoin block header
function getBlockTimestamp(blockHeader) {
  const headerBin = fromHex(blockHeader).slice(0, 80);
  const timestamp = headerBin[68] + 256 * headerBin[69] + 256 * 256 * headerBin[70] + 256 * 256 * 256 * headerBin[71];
  return timestamp;
}

// Get difficulty bits from block header
function getBlockDifficultyBits(blockHeader) {
  const headerBin = fromHex(blockHeader).slice(0, 80);
  const bits = headerBin[72] + 256 * headerBin[73] + 256 * 256 * headerBin[74] + 256 * 256 * 256 * headerBin[75];
  return bits;
}

// Get difficulty from dogecoin block header
function getBlockDifficulty(blockHeader) {
  const headerBin = fromHex(blockHeader).slice(0, 80);
  const exp = new BN(headerBin[75]);
  const mant = new BN(headerBin[72] + 256 * headerBin[73] + 256 * 256 * headerBin[74]);
  const target = mant.mul(new BN(256).pow(exp.subn(3)));
  const difficulty1 = new BN(0x00FFFFF).mul(new BN(256).pow(new BN(0x1e-3)));
  const difficulty = difficulty1.div(target);
  return difficulty1.div(target);
}

const timeout = async (ms) => new Promise((resolve, reject) => setTimeout(resolve, ms));

const blockchainTimeoutSeconds = async (s) => {
  await web3.currentProvider.send({
    jsonrpc: '2.0',
    method: 'evm_increaseTime',
    params: [s],
    id: 0,
  }, function(error, result) {});
};

const mineBlocks = async (web3, n) => {
  for (let i = 0; i < n; i++) {
    await web3.currentProvider.send({
      jsonrpc: '2.0',
      method: 'evm_mine',
      params: [],
      id: 0,
    }, function(error, result) {});
    await timeout(100);
  }
}

const getBlockNumber = () => new Promise((resolve, reject) => {
  web3.eth.getBlockNumber((err, res) => {
    if (err) {
      reject(err);
    } else {
      resolve(res);
    }
  });
});

// Helper to assert a promise failing
async function verifyThrow(P, cond, message) {
  let e;
  try {
    await P();
  } catch (ex) {
    e = ex;
  }
  assert.throws(() => {
    if (e) {
      throw e;
    }
  }, cond, message);
}

// Format a numeric or hexadecimal string to solidity uint256
function toUint256(value) {
  if (typeof value === 'string') {
    // Assume data is hex formatted
    value = remove0x(value);
  } else {
    // Number or BignNumber
    value = value.toString(16);
  }
  return formatHexUint32(value);
}

// Format a numeric or hexadecimal string to solidity uint32
function toUint32(value) {
  if (typeof value === 'string') {
    // Assume data is hex formatted
    value = remove0x(value);
  } else {
    // Number or BignNumber
    value = value.toString(16);
  }
  // Format as 4 bytes = 8 hexadecimal chars
  return formatHexUint(value, 8);
}

// Calculate a superblock id
function calcSuperblockHash(merkleRoot, accumulatedWork, timestamp, prevTimestamp, lastHash, lastBits, parentId) {
  return `0x${Buffer.from(keccak256.arrayBuffer(
    Buffer.concat([
      fromHex(merkleRoot),
      fromHex(toUint256(accumulatedWork)),
      fromHex(toUint256(timestamp)),
      fromHex(toUint256(prevTimestamp)),
      fromHex(lastHash),
      fromHex(toUint32(lastBits)),
      fromHex(parentId)
    ])
  )).toString('hex')}`;
}

// Construct a superblock from an array of block headers
function makeSuperblock(headers, parentId, parentAccumulatedWork, parentTimestamp = 0) {
  if (headers.length < 1) {
    throw new Error('Requires at least one header to build a superblock');
  }
  const blockHashes = headers.map(header => calcBlockSha256Hash(header));
  const accumulatedWork = headers.reduce((work, header) => work.add(getBlockDifficulty(header)), new BN(parentAccumulatedWork));
  const merkleRoot = makeMerkle(blockHashes);
  const timestamp = getBlockTimestamp(headers[headers.length - 1]);
  const prevTimestamp = (headers.length >= 2) ? getBlockTimestamp(headers[headers.length - 2])
    : parentTimestamp;
  const lastBits = getBlockDifficultyBits(headers[headers.length - 1]);
  const lastHash = calcBlockSha256Hash(headers[headers.length - 1]);
  return {
    merkleRoot,
    accumulatedWork: accumulatedWork.toString(),
    timestamp,
    prevTimestamp,
    lastHash,
    lastBits,
    parentId,
    superblockHash: calcSuperblockHash(
      merkleRoot,
      accumulatedWork,
      timestamp,
      prevTimestamp,
      lastHash,
      lastBits,
      parentId,
    ),
    blockHeaders: headers,
    blockHashes: blockHashes.map(x => x.slice(2)), // <- remove prefix '0x'
  };
}

function forgeDogeBlockHeader(prevHash, time) {
  const version = "03006200";
  const merkleRoot = "0".repeat(56) + "deadbeef";
  const bits = "ffff7f20";
  const nonce = "feedbeef";
  return version + prevHash + merkleRoot + time + bits + nonce;
}

function formatHexUint(str, length) {
  while (str.length < length) {
    str = "0" + str;
  }
  return str;
}

function base58ToBytes20(str) {
    let decoded = bitcoreLib.encoding.Base58Check.decode(str);
    return "0x" + decoded.toString('hex').slice(2, 42);
}

function findEvent(logs, name) {
  const index = logs.findIndex(log => log.event === name);
  return index >= 0 ? logs[index] : undefined;
}

const DOGECOIN = {
  /**
   * Message prefix used in dogecoin `signmessage` node API
   */
  messagePrefix: '\x19Dogecoin Signed Message:\n',
  /**
   * BIP32 version bytes for dogecoin mainnet
   * See https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki
   */
  bip32: {
    /**
     * BIP32 version bytes for extended non-hardened keys
     */
    public: 0x02facafd,
    /**
     * BIP32 version bytes for extended hardened keys
     */
    private: 0x02fac398
  },
  /**
   * First byte of public key addresses for dogecoin
   */
  pubKeyHash: 0x1e,
  /**
   * First byte of script addresses for dogecoin
   */
  scriptHash: 0x16,
  /**
   * Network prefix
   * See https://en.bitcoin.it/wiki/Wallet_import_format
   */
  wif: 0x9e
};

function dogeKeyPairFromWIF(wif) {
  return bitcoin.ECPair.fromWIF(wif, DOGECOIN);
}

function dogeAddressFromKeyPair(keyPair) {
  return bitcoin.payments.p2pkh({ pubkey: keyPair.publicKey, network: DOGECOIN }).address;
}

function publicKeyHashFromKeyPair(keyPair) {
  return `0x${bitcoin.crypto.ripemd160(bitcoin.crypto.sha256(keyPair.publicKey)).toString('hex')}`;
}

function ethAddressFromKeyPair(keyPair) {
  const uncompressedPublicKey = bitcoin.ECPair.fromPublicKey(keyPair.publicKey, { compressed: false });
  return `0x${Buffer.from(keccak256.arrayBuffer(uncompressedPublicKey.publicKey.slice(1))).slice(12).toString('hex')}`;
}

/**
 * @param signer private key in WIF
 * @param inputs [[txid, index]] list of utxos where utxo = txid + index of output
 * @param outputs [[address, amount, data]] list of tx data
 */
function buildDogeTransaction({ signer, inputs, outputs }) {
  const txBuilder = new bitcoin.TransactionBuilder(DOGECOIN);
  txBuilder.setVersion(1);
  inputs.forEach(([ txid, index ]) => txBuilder.addInput(txid, index));
  outputs.forEach(([address, amount, data]) => {
    if (address === 'OP_RETURN') {
      const embed = bitcoin.payments.embed({ data: [data] });
      txBuilder.addOutput(embed.output, amount);
    } else {
      txBuilder.addOutput(address, amount);
    }
  });
  txBuilder.sign(0, signer);
  return txBuilder.build();
}


function formatHexUint32(str) {
  // To format 32 bytes is 64 hexadecimal characters
  return formatHexUint(str, 64);
}

function remove0x(str) {
  return (str.startsWith("0x")) ? str.substring(2) : str;
}

async function storeSuperblockFrom974401(superblocks, claimManager) {
  const { headers, hashes } = await parseDataFile('test/headers/11from974401DogeMain.txt');

  const genesisSuperblock = makeSuperblock(
    headers.slice(0, 1), // header 974401
    '0x0000000000000000000000000000000000000000000000000000000000000000',
    0,            // accumulated work block 974400
    1448429041    // timestamp block 974400
  );

  await superblocks.initialize(
    genesisSuperblock.merkleRoot,
    genesisSuperblock.accumulatedWork,
    genesisSuperblock.timestamp,
    genesisSuperblock.prevTimestamp,
    genesisSuperblock.lastHash,
    genesisSuperblock.lastBits,
    genesisSuperblock.parentId,
  );

  const proposedSuperblock = makeSuperblock(
    headers.slice(1),
    genesisSuperblock.superblockHash,
    genesisSuperblock.accumulatedWork,
  );

  await claimManager.makeDeposit({ value: DEPOSITS.MIN_PROPOSAL_DEPOSIT });

  let result = await claimManager.proposeSuperblock(
    proposedSuperblock.merkleRoot,
    proposedSuperblock.accumulatedWork,
    proposedSuperblock.timestamp,
    proposedSuperblock.prevTimestamp,
    proposedSuperblock.lastHash,
    proposedSuperblock.lastBits,
    proposedSuperblock.parentId,
  );
  let receipt = await result.wait();

  const superblockClaimCreatedEvents = receipt.events.filter((event) => event.event === "SuperblockClaimCreated");
  assert.lengthOf(superblockClaimCreatedEvents, 1, 'New superblock should be proposed');
  const superblockHash = receipt.events[1].args.superblockHash;

  await blockchainTimeoutSeconds(3*OPTIONS_DOGE_REGTEST.TIMEOUT);

  result = await claimManager.checkClaimFinished(superblockHash);
  receipt = await result.wait();
  const superblockClaimSuccessfulEvents = receipt.events.filter((event) => event.event === "SuperblockClaimSuccessful");
  assert.lengthOf(superblockClaimSuccessfulEvents, 1, 'Superblock claim should be successful');

  const headerAndHashes = {
    header: {
      nonce: 0,
      hash: 'b26fc6c25e9097aa7ced3610b45b2f018c5e4730822c9809d5ffb2a860b21b24',
      timestamp: 1448429204,
      merkle_root: 'ee7440781b99647989f3c254c3f3ac477feeed4f50ba265ab6c45bb045d29466',
      version: 6422787,
      prevhash: 'a10377b456caa4d7a57623ddbcdb4c81e20b4ddaece77396b717fe49488975a4',
      bits: 453226816,
      auxpow: 'realValueShouldBePutHere'
    },
    hashes: [
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
      '076a27faec1d71499c7946c974073e3a9d27fbdaf2a491df960669a122090b29',
    ],
    genesisSuperblock,
    proposedSuperblock,
  };
  return headerAndHashes;
}

// the inputs to makeMerkleProof can be computed by using pybitcointools:
// header = get_block_header_data(blocknum)
// hashes = get_txs_in_block(blocknum)
function makeMerkleProof(hashes, txIndex) {
    const proofOfFirstTx = btcProof.getProof(hashes, txIndex);
    return proofOfFirstTx.sibling;
}

// Adds the size of the hex string in bytes.
// For input "111111" will return "00000003111111"
function addSizeToHeader(input) {
  let size = input.length / 2; // 2 hex characters represent a byte
  size = size.toString(16);
  while (size.length < 8) {
    size = "0" + size;
  }
  return size + input;
}

// Convert an hexadecimal string to buffer
function fromHex(data) {
  return Buffer.from(remove0x(data), 'hex');
}

// Calculate the scrypt hash from a buffer
// hash = scryptHash(data, start, length)
function scryptHash(data, start = 0, length = 80) {
  const buff = Buffer.from(data, start, length);
  return scryptsy(buff, buff, 1024, 1, 1, 32)
}

// Calculate PoW hash from dogecoin header
function calcHeaderPoW(header) {
  const headerBin = fromHex(header);
  if (isHeaderAuxPoW(headerBin)) {
    const length = headerBin.length;
    return scryptHash(headerBin.slice(length - 80, length)).toString('hex');
  }
  return scryptHash(headerBin).toString('hex');
}

// Return true when the block header contains a AuxPoW
function isHeaderAuxPoW(headerBin) {
  return (headerBin[1] & 0x01) != 0;
}

function bigNumberArrayToNumberArray(input) {
  return input.map((element) => element.toNumber());
}

function operatorSignItsEthAddress(operatorPrivateKeyString, operatorEthAddress) {
    // bitcoreLib.PrivateKey marks the private key as compressed if it receives a String as a parameter.
    // bitcoreLib.PrivateKey marks the private key as uncompressed if it receives a Buffer as a parameter.
    // In fact, private keys are not compressed/uncompressed. The compressed/uncompressed attribute
    // is used when generating a compressed/uncompressed public key from the private key.
    // Ethereum addresses are first 20 bytes of keccak256(uncompressed public key)
    // Dogecoin public key hashes are calculated: ripemd160((sha256(compressed public key));
    const operatorPrivateKeyCompressed = bitcoreLib.PrivateKey(remove0x(operatorPrivateKeyString));
    const operatorPrivateKeyUncompressed = bitcoreLib.PrivateKey(fromHex(operatorPrivateKeyString))
    const operatorPublicKeyCompressedString = "0x" + operatorPrivateKeyCompressed.toPublicKey().toString();

    // Generate the msg to be signed: double sha256 of operator eth address
    const operatorEthAddressHash = bitcoreLib.crypto.Hash.sha256sha256(fromHex(operatorEthAddress));

    // Operator private key uncompressed sign msg
    const ecdsa = new ECDSA();
    ecdsa.hashbuf = operatorEthAddressHash;
    ecdsa.privkey = operatorPrivateKeyUncompressed;
    ecdsa.pubkey = operatorPrivateKeyUncompressed.toPublicKey();
    ecdsa.signRandomK();
    ecdsa.calci();
    const ecdsaSig = ecdsa.sig;
    const signature = "0x" + ecdsaSig.toCompact().toString('hex');
    return [operatorPublicKeyCompressedString, signature];
}

module.exports = {
  OPTIONS_DOGE_REGTEST,
  DOGE_MAINNET,
  DOGE_TESTNET,
  DOGE_REGTEST,
  DEPOSITS,
  formatHexUint32,
  remove0x,
  storeSuperblockFrom974401,
  makeMerkleProof,
  addSizeToHeader,
  fromHex,
  scryptHash,
  parseDataFile,
  calcHeaderPoW,
  isHeaderAuxPoW,
  bigNumberArrayToNumberArray,
  formatHexUint,
  makeMerkle,
  hashesToData,
  headerToData,
  calcBlockSha256Hash,
  getBlockTimestamp,
  getBlockDifficultyBits,
  getBlockDifficulty,
  timeout,
  blockchainTimeoutSeconds,
  mineBlocks,
  getBlockNumber,
  verifyThrow,
  calcSuperblockHash,
  makeSuperblock,
  operatorSignItsEthAddress,
  forgeDogeBlockHeader,
  base58ToBytes20,
  findEvent,
  dogeKeyPairFromWIF,
  dogeAddressFromKeyPair,
  publicKeyHashFromKeyPair,
  buildDogeTransaction,
  ethAddressFromKeyPair,
};

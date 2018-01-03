var fs = require('fs');
var readline = require('readline');
var btcProof = require('bitcoin-proof');
var scryptsy = require('scryptsy');

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


module.exports = {
  formatHexUint32: function (str) {
    while (str.length < 64) {
      str = "0" + str;
    }
    return str;
  }
  ,
  remove0x: function (str) {
    return (str.indexOf("0x")==0) ? str.substring(2) : str;
  }
  ,
  bulkStore10From974401: function (dr, accounts) {
    return new Promise((resolve, reject) => {

      var startBlockNum = 974401;
      var headers = "0x";
      var hashes = "0x";
      var numBlock = 10;
      var block974401Prev = "0xa84956d6535a1be26b77379509594bdb8f186b29c3b00143dcb468015bdd16da";

      dr.setInitialParent(block974401Prev, startBlockNum-1, 1, {from: accounts[0]})
      .then(async (result) => {
          const { headers: rawHeaders, hashes: rawHashes } = await parseDataFile('test/headers/11from974401DogeMain.txt');
          headers += rawHeaders.map(module.exports.addSizeToHeader).join('');
          hashes += rawHeaders.map(module.exports.calcHeaderPoW).join('');
          return dr.bulkStoreHeaders(headers, hashes, numBlock, {from: accounts[0]});
      }).then(function(result) {
      	//console.log(result.receipt.logs);
        return dr.getBestBlockHeight.call();
      }).then(
        function(result) {
          assert.equal(result.toNumber(), startBlockNum + numBlock - 1, "latest block number is not the expected one"); // # +1 since setInitialParent was called with imaginary block
          //return dr.getAverageChainWork.call();
          var headerAndHashes = {
            'header' : {'nonce': 0, 'hash': 'b26fc6c25e9097aa7ced3610b45b2f018c5e4730822c9809d5ffb2a860b21b24', 'timestamp': 1448429204, 'merkle_root': 'ee7440781b99647989f3c254c3f3ac477feeed4f50ba265ab6c45bb045d29466', 'version': 6422787, 'prevhash': 'a10377b456caa4d7a57623ddbcdb4c81e20b4ddaece77396b717fe49488975a4', 'bits': 453226816, 'auxpow' : 'realValueShouldBePutHere'},
            'hashes' : ['5c090206d5ccc1827ca7cb723b9f706a1ed8c9bb17d9dc0c7188c2ee10a7501c', 'af12afe762daf75815db0097e16445dbba45ce9140f3da37b86f00b45bd627b2', '718add98dca8f54288b244dde3b0e797e8fe541477a08ef4b570ea2b07dccd3f', '0c1c11cc899dfa6f01477e82969c5b2c07f934445bbf116c15f6d06541bc52da', '0c6fcfd484ff722d3c512bf38c38904fb75fefdd16d187827887259573d4da6d', 'd85837d895dc1f38104366a7c2dfe6290f7175d2a69240ebe8bb36ffc52ed4d3', '755b9f137575fe9a8dfc984673f62e80b2eba3b3b8f8000a799a3f14730dbe72', '42cf9e7db40d99edd323d786d56f6be8159a7e7be458418917b02b2b3be51684', 'cc8c0f43a1e2100c5b9841495ed1f123f2e3b0a2411c43234526347609034588', '89d95e9f1d627bb810ea6799b6f7bd79776bc60a3d61cb40f537c3cba9d53865', '271f317be9122894e6aef9491a877418ebb82f8de53615d3de8e8403bdbbe38b', '3aaed4666225d73f4fd40ccf0602cbc3555c0969ba5f909e56e11da14ddb44b9', '2f28d3ff74af7e5621ba8947dc20792cc5e082283f00cd4fb8475b18f0531c3c', '6c9065e5f18e498806e3a483af4a0cb928886f6ba0a97b1134dade772351ff46', '73307cd2527f6fbc736bfc7a6eb692a283bc647aab650863a8ca8ea7a60c4fa0', '649ca5456c1cca1c5cf2c17a527208957a75e42b22e651c5e8f43e8647e01b2f', '25a51303b4b9e648bb1fb66b4aff5e2c46e4cd99646bda975f2347e709acabdb', 'f88050416d4efbd9940d582f67f5cda3db4414dd35db269ab72d8a7981a74605', 'ff96cf9beaed0c31a633c3c0c87f4e040bd4f042998c787ace9c07245ad7dee7', 'b625dc14e0c402f6d6e3c9beac35fb5aaa5db83c04ef7dfdd508d29e49aacf64', 'f8b195ba046226b4ca040a482e7a823bfcb2d61d9733f5689d0d99c8d6795076', '877973b213eb921161777b96fdd50f9bc4701b13de8842e7c940b9daa3e91baa', '076a27faec1d71499c7946c974073e3a9d27fbdaf2a491df960669a122090b29']
          }
          return headerAndHashes;
        }
      ).then(resolve);
    });
  }
  ,
  // the inputs to makeMerkleProof can be computed by using pybitcointools:
  // header = get_block_header_data(blocknum)
  // hashes = get_txs_in_block(blocknum)
  makeMerkleProof: function (hashes, txIndex) {
      var proofOfFirstTx = btcProof.getProof(hashes, txIndex);
      return proofOfFirstTx.sibling;
  }
  ,
  // Adds the size of the hex string in bytes.
  // For input "111111" will return "00000003111111"
  addSizeToHeader: function (input) {
    var size = input.length / 2; // 2 hex characters represent a byte
    size = size.toString(16);
    while (size.length < 8) {
      size = "0" + size;
    }
    return size + input;
  },
  // Convert an hexadecimal string to buffer
  fromHex: function (data) {
    return Buffer.from(module.exports.remove0x(data), 'hex');
  },
  // Calculate the scrypt hash from a buffer
  // hash = scryptHash(data, start, length)
  scryptHash: function (data, start = 0, length = 80) {
    let buff = Buffer.from(data, start, length);
    return scryptsy(buff, buff, 1024, 1, 1, 32)
  },
  // Parse a data file returns a struct with headers and hashes
  parseDataFile,
  // Calculate PoW hash from dogecoin header
  calcHeaderPoW: function (header) {
    const headerBin = module.exports.fromHex(header);
    if (module.exports.isHeaderAuxPoW(headerBin)) {
      const length = headerBin.length;
      return module.exports.scryptHash(headerBin.slice(length - 80, length)).toString('hex');
    }
    return module.exports.scryptHash(headerBin).toString('hex');
  },
  // Return true when the block header contains a AuxPoW
  isHeaderAuxPoW: function (headerBin) {
    return (headerBin[1] & 0x01) != 0;
  }
};

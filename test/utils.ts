import BN from "bn.js";
import type { ContractReceipt, Event } from "ethers";
import hre from "hardhat";
import { sha256 } from "js-sha256";
import { keccak256 } from "js-sha3";
import scryptsy from "scryptsy";

import bitcoin = require("bitcoinjs-lib");
const bitcoreLib = require("bitcore-lib");
const btcProof = require("bitcoin-proof");
const ECDSA = bitcoreLib.crypto.ECDSA;

interface MerkleProof {
  txId: string;
  txIndex: number;
  sibling: string[];
}

export const OPTIONS_DOGE_REGTEST = {
  DURATION: 600, // 10 minute
  DELAY: 60, // 1 minute
  TIMEOUT: 15, // 15 seconds
  CONFIRMATIONS: 1, // Superblocks required to confirm semi approved superblock
  REWARD: 3, // Monetary reward for opponent in case battle is lost
};

export const DOGE_MAINNET = 0;
export const DOGE_TESTNET = 1;
export const DOGE_REGTEST = 2;

export const DEPOSITS = {
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
  VERIFY_SUPERBLOCK_COST: 220000,
};

// Calculates the merkle root from an array of hashes
// The hashes are expected to be 32 bytes in hexadecimal
export function makeMerkle(hashes: string[]): string {
  if (hashes.length === 0) {
    throw new Error("Cannot compute merkle tree of an empty array");
  }

  return `0x${btcProof.getMerkleRoot(hashes.map(toUint256).map(remove0x))}`;
}

// Calculates the double sha256 of a block header
// Block header is expected to be in hexadecimal
export function calcBlockSha256Hash(blockHeader: string): string {
  const headerBin = fromHex(blockHeader).slice(0, 80);
  return `0x${Buffer.from(sha256.array(sha256.arrayBuffer(headerBin)))
    .reverse()
    .toString("hex")}`;
}

// Get timestamp from dogecoin block header
function getBlockTimestamp(blockHeader: string) {
  const headerBin = fromHex(blockHeader).slice(0, 80);
  const timestamp =
    headerBin[68] +
    256 * headerBin[69] +
    256 * 256 * headerBin[70] +
    256 * 256 * 256 * headerBin[71];
  return timestamp;
}

// Get difficulty bits from block header
function getBlockDifficultyBits(blockHeader: string) {
  const headerBin = fromHex(blockHeader).slice(0, 80);
  const bits =
    headerBin[72] +
    256 * headerBin[73] +
    256 * 256 * headerBin[74] +
    256 * 256 * 256 * headerBin[75];
  return bits;
}

// Get difficulty from dogecoin block header
function getBlockDifficulty(blockHeader: string) {
  const headerBin = fromHex(blockHeader).slice(0, 80);
  const exp = new BN(headerBin[75]);
  const mant = new BN(
    headerBin[72] + 256 * headerBin[73] + 256 * 256 * headerBin[74]
  );
  const target = mant.mul(new BN(256).pow(exp.subn(3)));
  const difficulty1 = new BN(0x00fffff).mul(new BN(256).pow(new BN(0x1e - 3)));
  const difficulty = difficulty1.div(target);
  return difficulty;
}

export function blockchainTimeoutSeconds(seconds: number): Promise<string> {
  return hre.network.provider.request({
    method: "evm_increaseTime",
    params: [seconds],
  }) as Promise<string>;
}

export async function mineBlocks(n: number): Promise<void> {
  for (let i = 0; i < n; i++) {
    await hre.network.provider.request({
      method: "evm_mine",
      params: [],
    });
  }
}

// Format a numeric or hexadecimal string to solidity uint256
function toUint256(value: string) {
  // uint256 size in bytes
  const uint256Size = 32;
  return hre.ethers.utils.hexZeroPad(value, uint256Size);
}

// Format a numeric or hexadecimal string to solidity uint32
function toUint32(value: string) {
  // uint32 size in bytes
  const uint32Size = 4;
  return hre.ethers.utils.hexZeroPad(value, uint32Size);
}

// Calculate a superblock id
export function calcSuperblockHash(
  merkleRoot: string,
  accumulatedWork: string,
  timestamp: string,
  prevTimestamp: string,
  lastHash: string,
  lastBits: string,
  parentId: string
): string {
  return `0x${Buffer.from(
    keccak256.arrayBuffer(
      Buffer.concat([
        fromHex(merkleRoot),
        fromHex(toUint256(accumulatedWork)),
        fromHex(toUint256(timestamp)),
        fromHex(toUint256(prevTimestamp)),
        fromHex(lastHash),
        fromHex(toUint32(lastBits)),
        fromHex(parentId),
      ])
    )
  ).toString("hex")}`;
}

// Construct a superblock from an array of block headers
export function makeSuperblock(
  headers: string[],
  parentId: string,
  parentAccumulatedWork: number | string,
  parentTimestamp = 0
) {
  if (headers.length < 1) {
    throw new Error("Requires at least one header to build a superblock");
  }
  const blockHashes = headers.map((header) => calcBlockSha256Hash(header));
  const accumulatedWork = headers.reduce(
    (work, header) => work.add(getBlockDifficulty(header)),
    new BN(parentAccumulatedWork)
  );
  const merkleRoot = makeMerkle(blockHashes);
  const timestamp = getBlockTimestamp(headers[headers.length - 1]);
  const prevTimestamp =
    headers.length >= 2
      ? getBlockTimestamp(headers[headers.length - 2])
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
      `0x${accumulatedWork.toString("hex")}`,
      hre.ethers.utils.hexlify(timestamp),
      hre.ethers.utils.hexlify(prevTimestamp),
      lastHash,
      hre.ethers.utils.hexlify(lastBits),
      parentId
    ),
    blockHeaders: headers,
    blockHashes: blockHashes.map(remove0x),
  };
}

export function base58ToBytes20(str: string): string {
  const decoded = bitcoreLib.encoding.Base58Check.decode(str);
  return `0x${decoded.toString("hex").slice(2, 42)}`;
}

export function findEvent(
  events: ContractReceipt["events"],
  name: string
): Event | undefined {
  if (events === undefined) {
    // TODO: return undefined instead?
    throw new Error("No events found on receipt!");
  }
  return events.find((log) => log.event === name);
}

const DOGECOIN = {
  /**
   * Message prefix used in dogecoin `signmessage` node API
   */
  messagePrefix: "\x19Dogecoin Signed Message:\n",
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
    private: 0x02fac398,
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
  wif: 0x9e,
  bech32: "not a prefix",
};

export function dogeKeyPairFromWIF(wif: string): bitcoin.ECPairInterface {
  return bitcoin.ECPair.fromWIF(wif, DOGECOIN);
}

// keyPair should be the output of dogeKeyPairFromWIF
export function dogeAddressFromKeyPair(
  keyPair: bitcoin.ECPairInterface
): string {
  const { address } = bitcoin.payments.p2pkh({
    pubkey: keyPair.publicKey,
    network: DOGECOIN,
  });
  if (address === undefined) {
    throw new Error("Could not retrieve address.");
  }
  return address;
}

// keyPair should be the output of dogeKeyPairFromWIF
export function publicKeyHashFromKeyPair(
  keyPair: bitcoin.ECPairInterface
): string {
  return `0x${bitcoin.crypto
    .ripemd160(bitcoin.crypto.sha256(keyPair.publicKey))
    .toString("hex")}`;
}

interface TxInput {
  txId: string;
  index: number;
}

type TxOutput = PaymentTxOutput | DataTxOutput;

interface PaymentTxOutput {
  type: "payment";
  address: string;
  value: number;
}

/* eslint-disable-next-line @typescript-eslint/no-explicit-any */
function isPaymentTxOutput(txOut: any): txOut is PaymentTxOutput {
  return typeof txOut === "object" && txOut.type === "payment";
}

interface DataTxOutput {
  type: "data embed";
  value: 0;
  data: Buffer;
}

/* eslint-disable-next-line @typescript-eslint/no-explicit-any */
function isDataTxOutput(txOut: any): txOut is DataTxOutput {
  return typeof txOut === "object" && txOut.type === "data embed";
}

/**
 * @param signer private key in WIF
 * @param inputs [[txid, index]] list of utxos where utxo = txid + index of output
 * @param outputs [[address, amount, data]] list of tx data
 */
export function buildDogeTransaction({
  signer,
  inputs,
  outputs,
}: {
  signer: bitcoin.ECPair.Signer;
  inputs: TxInput[];
  outputs: TxOutput[];
}): bitcoin.Transaction {
  const txBuilder = new bitcoin.TransactionBuilder(DOGECOIN);
  txBuilder.setVersion(1);
  inputs.forEach(({ txId, index }) => txBuilder.addInput(txId, index));
  outputs.forEach((txOut) => {
    if (isDataTxOutput(txOut)) {
      const embed = bitcoin.payments.embed({ data: [txOut.data] });
      txBuilder.addOutput(embed.output!, txOut.value);
    } else {
      txBuilder.addOutput(txOut.address, txOut.value);
    }
  });
  txBuilder.sign(0, signer);
  return txBuilder.build();
}

export function remove0x(str: string) {
  return str.startsWith("0x") ? str.substring(2) : str;
}

// the inputs to makeMerkleProof can be computed by using pybitcointools:
// header = get_block_header_data(blocknum)
// hashes = get_txs_in_block(blocknum)
export function makeMerkleProof(hashes: string[], txIndex: number): MerkleProof {
  const proofOfFirstTx: MerkleProof = btcProof.getProof(hashes, txIndex);
  return proofOfFirstTx;
}

// Convert an hexadecimal string to buffer
function fromHex(data: string) {
  return Buffer.from(remove0x(data), "hex");
}

// Calculate the scrypt hash from a buffer
// hash = scryptHash(data, start, length)
function scryptHash(data: Buffer, start = 0, length = 80) {
  const buff = Buffer.from(data, start, length);
  return scryptsy(buff, buff, 1024, 1, 1, 32);
}

// Calculate PoW hash from dogecoin header
export function calcHeaderPoW(header: string): string {
  const headerBin = fromHex(header);
  if (isHeaderAuxPoW(headerBin)) {
    const length = headerBin.length;
    return scryptHash(headerBin.slice(length - 80, length)).toString("hex");
  }
  return scryptHash(headerBin).toString("hex");
}

// Return true when the block header contains a AuxPoW
function isHeaderAuxPoW(headerBin: Buffer) {
  return (headerBin[1] & 0x01) !== 0;
}

export function operatorSignItsEthAddress(
  operatorPrivateKey: string,
  operatorEthAddress: string
): string[] {
  // bitcoreLib.PrivateKey marks the private key as compressed if it receives a String as a parameter.
  // bitcoreLib.PrivateKey marks the private key as uncompressed if it receives a Buffer as a parameter.
  // In fact, private keys are not compressed/uncompressed. The compressed/uncompressed attribute
  // is used when generating a compressed/uncompressed public key from the private key.
  // Ethereum addresses are first 20 bytes of keccak256(uncompressed public key)
  // Dogecoin public key hashes are calculated: ripemd160((sha256(compressed public key));
  const operatorPrivateKeyCompressed = bitcoreLib.PrivateKey(
    remove0x(operatorPrivateKey)
  );
  const operatorPrivateKeyUncompressed = bitcoreLib.PrivateKey(
    fromHex(operatorPrivateKey)
  );
  const operatorPublicKeyCompressedString =
    "0x" + operatorPrivateKeyCompressed.toPublicKey().toString();

  // Generate the msg to be signed: double sha256 of operator eth address
  const operatorEthAddressHash = bitcoreLib.crypto.Hash.sha256sha256(
    fromHex(operatorEthAddress)
  );

  // Operator private key uncompressed sign msg
  const ecdsa = new ECDSA();
  ecdsa.hashbuf = operatorEthAddressHash;
  ecdsa.privkey = operatorPrivateKeyUncompressed;
  ecdsa.pubkey = operatorPrivateKeyUncompressed.toPublicKey();
  ecdsa.signRandomK();
  ecdsa.calci();
  const ecdsaSig = ecdsa.sig;
  const signature = "0x" + ecdsaSig.toCompact().toString("hex");
  return [operatorPublicKeyCompressedString, signature];
}

export function isolateTests(): void {
  let snapshot: any;

  before(async function () {
    snapshot = await hre.network.provider.request({
      method: "evm_snapshot",
      params: [],
    });
  });

  // TODO: allow defining test suites here?
  // It would ensure proper nesting of other `before` and `after` mocha directives

  after(async function () {
    await hre.network.provider.request({
      method: "evm_revert",
      params: [snapshot],
    });
  });
}
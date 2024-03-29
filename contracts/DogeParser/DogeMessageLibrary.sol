// SPDX-License-Identifier: Apache-2.0

// Bitcoin transaction parsing library - modified for DOGE

// Copyright 2016 rain <https://keybase.io/rain>
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// https://en.bitcoin.it/wiki/Protocol_documentation#tx
//
// Raw Bitcoin transaction structure:
//
// field     | size | type     | description
// version   | 4    | int32    | transaction version number
// n_tx_in   | 1-9  | var_int  | number of transaction inputs
// tx_in     | 41+  | tx_in[]  | list of transaction inputs
// n_tx_out  | 1-9  | var_int  | number of transaction outputs
// tx_out    | 9+   | tx_out[] | list of transaction outputs
// lock_time | 4    | uint32   | block number / timestamp at which tx locked
//
// Transaction input (tx_in) structure:
//
// field      | size | type     | description
// previous   | 36   | outpoint | Previous output transaction reference
// script_len | 1-9  | var_int  | Length of the signature script
// sig_script | ?    | uchar[]  | Script for confirming transaction authorization
// sequence   | 4    | uint32   | Sender transaction version
//
// OutPoint structure:
//
// field      | size | type     | description
// hash       | 32   | char[32] | The hash of the referenced transaction
// index      | 4    | uint32   | The index of this output in the referenced transaction
//
// Transaction output (tx_out) structure:
//
// field         | size | type     | description
// value         | 8    | int64    | Transaction value (Satoshis)
// pk_script_len | 1-9  | var_int  | Length of the public key script
// pk_script     | ?    | uchar[]  | Public key as a Bitcoin script.
//
// Variable integers (var_int) can be encoded differently depending
// on the represented value, to save space. Variable integers always
// precede an array of a variable length data type (e.g. tx_in).
//
// Variable integer encodings as a function of represented value:
//
// value           | bytes  | format
// <0xFD (253)     | 1      | uint8
// <=0xFFFF (65535)| 3      | 0xFD followed by length as uint16
// <=0xFFFF FFFF   | 5      | 0xFE followed by length as uint32
// -               | 9      | 0xFF followed by length as uint64
//
// Public key scripts `pk_script` are set on the output and can
// take a number of forms. The regular transaction script is
// called 'pay-to-pubkey-hash' (P2PKH):
//
// OP_DUP OP_HASH160 <pubKeyHash> OP_EQUALVERIFY OP_CHECKSIG
//
// OP_x are Bitcoin script opcodes. The bytes representation (including
// the 0x14 20-byte stack push) is:
//
// 0x76 0xA9 0x14 <pubKeyHash> 0x88 0xAC
//
// The <pubKeyHash> is the ripemd160 hash of the sha256 hash of
// the public key, preceded by a network version byte. (21 bytes total)
//
// Network version bytes: 0x00 (mainnet); 0x6f (testnet); 0x34 (namecoin)
//
// The Bitcoin address is derived from the pubKeyHash. The binary form is the
// pubKeyHash, plus a checksum at the end.  The checksum is the first 4 bytes
// of the (32 byte) double sha256 of the pubKeyHash. (25 bytes total)
// This is converted to base58 to form the publicly used Bitcoin address.
// Mainnet P2PKH transaction scripts are to addresses beginning with '1'.
//
// P2SH ('pay to script hash') scripts only supply a script hash. The spender
// must then provide the script that would allow them to redeem this output.
// This allows for arbitrarily complex scripts to be funded using only a
// hash of the script, and moves the onus on providing the script from
// the spender to the redeemer.
//
// The P2SH script format is simple:
//
// OP_HASH160 <scriptHash> OP_EQUAL
//
// 0xA9 0x14 <scriptHash> 0x87
//
// The <scriptHash> is the ripemd160 hash of the sha256 hash of the
// redeem script. The P2SH address is derived from the scriptHash.
// Addresses are the scriptHash with a version prefix of 5, encoded as
// Base58check. These addresses begin with a '3'.

pragma solidity ^0.7.6;

// parse a raw Dogecoin transaction byte array
library DogeMessageLibrary {
  uint256 constant p = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f; // secp256k1
  uint256 constant q = (p + 1) / 4;

  // Offset for the transaction inputs.
  // This offset is constant because the version field is of fixed size.
  uint256 constant TX_INPUTS_OFFSET = 4;

  // Error codes
  uint256 constant ERR_INVALID_HEADER = 10050;
  uint256 constant ERR_COINBASE_INDEX = 10060; // coinbase tx index within Litecoin merkle isn't 0
  uint256 constant ERR_NOT_MERGE_MINED = 10070; // trying to check AuxPoW on a block that wasn't merge mined
  uint256 constant ERR_FOUND_TWICE = 10080; // 0xfabe6d6d found twice
  uint256 constant ERR_NO_MERGE_HEADER = 10090; // 0xfabe6d6d not found
  uint256 constant ERR_NOT_IN_FIRST_20 = 10100; // chain Merkle root isn't in the first 20 bytes of coinbase tx
  uint256 constant ERR_CHAIN_MERKLE = 10110;
  uint256 constant ERR_PARENT_MERKLE = 10120;
  uint256 constant ERR_PROOF_OF_WORK = 10130;

  enum Network {
    MAINNET,
    TESTNET,
    REGTEST
  }

  // AuxPoW block fields
  struct AuxPoW {
    uint256 scryptHash;
    uint256 txHash;
    uint256 coinbaseMerkleRoot; // Merkle root of auxiliary block hash tree; stored in coinbase tx field
    uint256[] chainMerkleProof; // proves that a given Dogecoin block hash belongs to a tree with the above root
    uint256 dogeHashIndex; // index of Doge block hash within block hash tree
    uint256 coinbaseMerkleRootCode; // encodes whether or not the root was found properly
    uint256 parentMerkleRoot; // Merkle root of transaction tree from parent Litecoin block header
    uint256[] parentMerkleProof; // proves that coinbase tx belongs to a tree with the above root
    uint256 coinbaseTxIndex; // index of coinbase tx within Litecoin tx tree
    uint256 parentNonce;
  }

  // Dogecoin block header stored as a struct, mostly for readability purposes.
  // BlockHeader structs can be obtained by parsing a block header's first 80 bytes
  // with parseHeaderBytes.
  struct BlockHeader {
    uint32 version;
    uint32 time;
    uint32 bits;
    uint32 nonce;
    uint256 blockHash;
    uint256 prevBlock;
    uint256 merkleRoot;
  }

  // Describes the input and where its script can be found.
  struct InputDescriptor {
    // Byte offset where the input is located in the tx
    uint256 offset;
    // Byte offset where the signature script is located in the tx
    uint256 sigScriptOffset;
    // Length of the signature script
    uint256 sigScriptLength;
  }

  // Outpoints are references to a particular output in a tx.
  // At the time a transaction is built, an outpoint should
  // derreference to an unspent transaction output.
  struct Outpoint {
    // Tx id
    uint256 txHash;
    // Index of output consumed in tx
    uint32 txIndex;
  }

  struct P2PKHOutput {
    uint64 value;
    bytes20 publicKeyHash;
  }

  /**
   * Convert a variable integer into a Solidity numeric type.
   *
   * @return the integer as a uint256
   * @return the byte index after the var integer
   */
  function parseVarInt(bytes memory txBytes, uint256 pos) private pure returns (uint256, uint256) {
    // the first byte tells us how big the integer is
    uint8 ibit = uint8(txBytes[pos]);
    pos += 1; // skip ibit

    if (ibit < 0xfd) {
      return (ibit, pos);
    } else if (ibit == 0xfd) {
      return (readUint16LE(txBytes, pos), pos + 2);
    } else if (ibit == 0xfe) {
      return (readUint32LE(txBytes, pos), pos + 4);
    }
    /*if (ibit == 0xff)*/
    else {
      return (readUint64LE(txBytes, pos), pos + 8);
    }
  }

  // Read a uint16 value from buffer in little endian format.
  function readUint16LE(bytes memory data, uint256 pos) private pure returns (uint16) {
    return uint16(uint8(data[pos])) + (uint16(uint8(data[pos + 1])) << 8);
  }

  // Read a uint32 value from buffer in little endian format.
  function readUint32LE(bytes memory data, uint256 pos) private pure returns (uint32) {
    return
      uint32(uint8(data[pos])) +
      (uint32(uint8(data[pos + 1])) << 8) +
      (uint32(uint8(data[pos + 2])) << 16) +
      (uint32(uint8(data[pos + 3])) << 24);
  }

  // Read a uint64 value from buffer in little endian format.
  function readUint64LE(bytes memory data, uint256 pos) private pure returns (uint64) {
    return
      uint64(uint8(data[pos])) +
      (uint64(uint8(data[pos + 1])) << 8) +
      (uint64(uint8(data[pos + 2])) << 16) +
      (uint64(uint8(data[pos + 3])) << 24) +
      (uint64(uint8(data[pos + 4])) << 32) +
      (uint64(uint8(data[pos + 5])) << 40) +
      (uint64(uint8(data[pos + 6])) << 48) +
      (uint64(uint8(data[pos + 7])) << 56);
  }

  // Read uint256 value from buffer in little endian format.
  function readUint256LE(bytes memory data, uint256 start) private pure returns (uint256 res) {
    require(start + 31 < data.length, "Invalid uint256 LE read from buffer");
    for (uint256 i = 0; i < 32; i++) {
      res += uint256(uint8(data[i + start])) << (8 * i);
    }
  }

  // Read uint256 value from buffer in big endian format.
  function readUint256BE(bytes memory data, uint256 start) private pure returns (uint256 res) {
    require(start + 31 < data.length, "Invalid uint256 BE read from buffer");
    for (uint256 i = 0; i < 32; i++) {
      res += uint256(uint8(data[i + start])) << (8 * (31 - i));
    }
  }

  /**
   * @dev - Parses a specific input in a tx to return its outpoint, i.e., its tx output reference.
   * @param txBytes - tx byte array
   * @param txInputIndex - Output index in tx.
   * @return spentTxHash Tx hash of the outpoint.
   * @return spentTxIndex Tx index of the outpoint.
   */
  function getInputOutpoint(bytes memory txBytes, uint32 txInputIndex)
    internal
    pure
    returns (uint256 spentTxHash, uint32 spentTxIndex)
  {
    uint256 pos = TX_INPUTS_OFFSET;

    (
      spentTxHash,
      spentTxIndex, /*pos*/

    ) = getOutpointFromInputsByIndex(txBytes, pos, txInputIndex);
  }

  /**
   * @dev - Parses an unlock doge tx
   *   Inputs
   *   One or more inputs signed by the operator.
   *   The rest of the inputs are ignored.
   *
   *   Ouputs
   *   0. Output for the user. Must contain a P2PKH script.
   *   1. Optional. Operator change. Must contain a P2PKH script.
   *   The rest of the outputs are ignored
   *   If there is no change for the operator, the second output is ignored.
   *
   * @param txBytes - tx byte array
   * @param amountOfInputs - Amount of inputs expected to be parsed.
   * @param amountOfOutputs - Amount of outputs expected to be parsed.
   *        All parsed outputs must contain P2PKH scripts.
   * @return outpoints References to previous tx outputs that are consumed in this tx.
   * @return outputs P2PKH outputs parsed in the transaction.
   */
  function parseUnlockTransaction(
    bytes memory txBytes,
    uint256 amountOfInputs,
    uint256 amountOfOutputs
  ) internal pure returns (Outpoint[] memory outpoints, P2PKHOutput[] memory outputs) {
    uint256 pos = TX_INPUTS_OFFSET;

    (outpoints, pos) = getUnlockInputs(txBytes, pos, amountOfInputs);

    outputs = parseUnlockTxOutputs(txBytes, pos, amountOfOutputs);
    return (outpoints, outputs);
  }

  function getUnlockInputs(
    bytes memory txBytes,
    uint256 pos,
    uint256 amountOfInputs
  ) private pure returns (Outpoint[] memory, uint256) {
    InputDescriptor[] memory inputScripts;

    (inputScripts, pos) = scanInputs(txBytes, pos, amountOfInputs);

    Outpoint[] memory outpoints = new Outpoint[](inputScripts.length);
    for (uint256 i = 0; i < inputScripts.length; i++) {
      // We need to flip the tx hash bytes to have it in reversed byte order as specified in the protocol.
      // We could use internal byte order and flip the hash later on when necessary but
      // that would add complexity to the usage of these functions.
      // See https://github.com/bitcoin-dot-org/bitcoin.org/issues/580
      // Interpreting this value as a little endian uint256 lets us reverse it as soon as we read it.
      uint256 inputOffset = inputScripts[i].offset;
      outpoints[i].txHash = readUint256LE(txBytes, inputOffset);
      outpoints[i].txIndex = readUint32LE(txBytes, inputOffset + 32);
    }

    return (outpoints, pos);
  }

  /**
   * Determine the operator output, if any, and the value of the user output
   *   Ouputs
   *   0. Output for the user. Must contain a P2PKH script.
   *   1. Optional. Operator change. Must contain a P2PKH script.
   *   The rest of the outputs are ignored
   *   If there is no change for the operator, the second output is ignored.
   *
   * @param txBytes - tx byte array
   * @param pos - position to start parsing txBytes
   * @param amountOfOutputs - Amount of outputs expected to be parsed.
   *        All parsed outputs must contain P2PKH scripts.
   * @return outputs P2PKH outputs parsed in the transaction.
   *
   * Returns output amount, index and ethereum address
   */
  function parseUnlockTxOutputs(
    bytes memory txBytes,
    uint256 pos,
    uint256 amountOfOutputs
  ) private pure returns (P2PKHOutput[] memory) {
    uint256 nOutputs;
    (nOutputs, pos) = parseVarInt(txBytes, pos);
    require(amountOfOutputs <= nOutputs, "The unlock transaction doesn't have enough outputs.");

    P2PKHOutput[] memory outputs = new P2PKHOutput[](amountOfOutputs);

    for (uint256 i = 0; i < outputs.length; i++) {
      bytes20 userPublicKeyHash;
      uint64 userValue;
      (userPublicKeyHash, userValue, pos) = scanUnlockOutput(txBytes, pos);
      outputs[i].value = userValue;
      outputs[i].publicKeyHash = userPublicKeyHash;
    }

    return outputs;
  }

  // Scans a single output of an unlock transaction.
  // The output script should be a P2PKH script.
  // If this is not the case, the parsing fails with a revert.
  // Returns the value, offset and length of scripts of the output.
  function scanUnlockOutput(bytes memory txBytes, uint256 pos)
    private
    pure
    returns (
      bytes20,
      uint64,
      uint256
    )
  {
    uint64 outputValue = readUint64LE(txBytes, pos);
    pos += 8;

    uint256 outputScriptLength;
    (outputScriptLength, pos) = parseVarInt(txBytes, pos);
    uint256 outputScriptStart = pos;
    pos += outputScriptLength;

    bytes20 outputPublicKeyHash = parseP2PKHOutputScript(
      txBytes,
      outputScriptStart,
      outputScriptLength
    );

    return (outputPublicKeyHash, outputValue, pos);
  }

  // @dev - Parses a doge tx assuming it is a lock operation
  //
  // @param txBytes - tx byte array
  // @param expectedOperatorPKH - public key hash that is expected to be used as output or input
  // Outputs
  // @return outputValue - amount sent to the lock address in satoshis
  // @return lockDestinationEthAddress - address where tokens should be minted to
  // @return outputIndex - number of output where expectedOperatorPKH was found
  function parseLockTransaction(bytes memory txBytes, bytes20 expectedOperatorPKH)
    internal
    pure
    returns (
      uint256,
      address,
      uint32
    )
  {
    uint256 pos = TX_INPUTS_OFFSET;

    // Ignore inputs
    pos = skipInputs(txBytes, pos);

    address lockDestinationEthAddress;
    uint256 operatorTxOutputValue;
    (operatorTxOutputValue, lockDestinationEthAddress) = parseLockTxOutputs(
      expectedOperatorPKH,
      txBytes,
      pos
    );
    require(lockDestinationEthAddress != address(0x0));

    return (operatorTxOutputValue, lockDestinationEthAddress, 0);
  }

  /**
   * Parse operator output and embedded ethereum address in transaction outputs in tx
   *
   * @param expectedOperatorPKH - operator public key hash to look for
   * @param txBytes - tx byte array
   * @param pos - position to start parsing txBytes
   * Outputs
   * @return output value of operator output
   * @return lockDestinationEthAddress - Lock destination address if operator output and OP_RETURN output found, 0 otherwise
   *
   * Returns output amount, index and ethereum address
   */
  function parseLockTxOutputs(
    bytes20 expectedOperatorPKH,
    bytes memory txBytes,
    uint256 pos
  ) private pure returns (uint256, address) {
    /*
            Outputs
            0. Operator
            1. OP_RETURN with the ethereum address of the user
            2. Optional. Change output for the user. This output is ignored.
        */
    uint256 operatorOutputValue;
    uint256 operatorScriptStart;
    uint256 operatorScriptLength;
    uint256 ethAddressScriptStart;
    uint256 ethAddressScriptLength;
    (
      operatorOutputValue,
      operatorScriptStart,
      operatorScriptLength,
      ethAddressScriptStart,
      ethAddressScriptLength
    ) = scanLockOutputs(txBytes, pos);

    // Check tx is sending funds to an operator.
    bytes20 outputPublicKeyHash = parseP2PKHOutputScript(
      txBytes,
      operatorScriptStart,
      operatorScriptLength
    );
    require(
      outputPublicKeyHash == expectedOperatorPKH,
      "The first tx output does not have a P2PKH output script for an operator."
    );

    // Read the destination Ethereum address
    require(
      isEthereumAddress(txBytes, ethAddressScriptStart, ethAddressScriptLength),
      "The second tx output does not describe an ethereum address."
    );
    address lockDestinationEthAddress = readEthereumAddress(
      txBytes,
      ethAddressScriptStart,
      ethAddressScriptLength
    );

    return (operatorOutputValue, lockDestinationEthAddress);
  }

  // Scan the outputs of a lock transaction.
  // The first output in a lock transaction transfers value to an operator.
  // The second output in a lock transaction is an unspendable output with an ethereum address.
  // Returns the offsets and lengths of scripts for the first and second outputs and
  // the value of the first output.
  function scanLockOutputs(bytes memory txBytes, uint256 pos)
    private
    pure
    returns (
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    )
  {
    uint256 nOutputs;

    (nOutputs, pos) = parseVarInt(txBytes, pos);
    require(nOutputs == 2 || nOutputs == 3, "Lock transactions only have two or three outputs.");

    // Tx output 0 is for the operator
    // read value of the output for the operator
    uint256 operatorOutputValue = readUint64LE(txBytes, pos);
    pos += 8;

    // read the script length
    uint256 operatorScriptLength;
    (operatorScriptLength, pos) = parseVarInt(txBytes, pos);
    uint256 operatorScriptStart = pos;
    pos += operatorScriptLength;

    // Tx output 1 describes the ethereum address that should receive the dogecoin tokens
    // skip value
    pos += 8;

    uint256 ethAddressScriptLength;
    uint256 ethAddressScriptStart;
    (ethAddressScriptLength, ethAddressScriptStart) = parseVarInt(txBytes, pos);

    return (
      operatorOutputValue,
      operatorScriptStart,
      operatorScriptLength,
      ethAddressScriptStart,
      ethAddressScriptLength
    );
  }

  /**
   * Scan some inputs and find their script lengths.
   * The rest of the inputs are consumed but ignored otherwise.
   * @param desiredInputs Number of outputs to scan through. desiredInputs=0 => scan all.
   * If the amount of inputs is less than the desired inputs, the scan reverts the transaction.
   * @return Array of input descriptors.
   * @return The position where the outputs begin in the transaction.
   */
  function scanInputs(
    bytes memory txBytes,
    uint256 pos,
    uint256 desiredInputs
  ) private pure returns (InputDescriptor[] memory, uint256) {
    uint256 nInputs;
    uint256 halt;

    (nInputs, pos) = parseVarInt(txBytes, pos);

    require(desiredInputs <= nInputs, "The transaction doesn't have enough inputs.");

    if (desiredInputs == 0) {
      halt = nInputs;
    } else {
      halt = desiredInputs;
    }

    InputDescriptor[] memory inputs = new InputDescriptor[](halt);

    uint256 i;
    for (i = 0; i < halt; i++) {
      inputs[i].offset = pos;
      // skip outpoint
      pos += 36;
      uint256 scriptLength;
      (scriptLength, pos) = parseVarInt(txBytes, pos);
      inputs[i].sigScriptOffset = pos;
      inputs[i].sigScriptLength = scriptLength;
      // skip sig_script, seq
      pos += scriptLength + 4;
    }

    // Skip the rest of the inputs to consume them and obtain outputs offset.
    for (; i < nInputs; i++) {
      // skip outpoint
      pos += 36;

      uint256 scriptLength;
      (scriptLength, pos) = parseVarInt(txBytes, pos);

      // skip sig_script and seq
      pos += scriptLength + 4;
    }

    return (inputs, pos);
  }

  /**
   * Returns the nth input outpoint. Outpoints are the tx hash and output index within the tx.
   * Reverts if the index is out of bounds for the input array.
   * @return dogeTxHash Tx hash referenced in input.
   * @return dogeTxIndex Output index within referenced tx.
   */
  function getOutpointFromInputsByIndex(
    bytes memory txBytes,
    uint256 pos,
    uint256 index
  )
    private
    pure
    returns (
      uint256 dogeTxHash,
      uint32 dogeTxIndex,
      uint256
    )
  {
    uint256 n_inputs;

    (n_inputs, pos) = parseVarInt(txBytes, pos);

    require(index < n_inputs, "Requested index is out of bounds for input array in tx.");

    for (uint256 i = 0; i < index; i++) {
      // skip outpoint
      pos += 36;

      uint256 script_len;
      (script_len, pos) = parseVarInt(txBytes, pos);

      // skip sig_script and seq
      pos += script_len + 4;
    }

    // We need to flip the tx hash bytes to have it in reversed byte order as specified in the protocol.
    // We could use internal byte order and flip the hash later on when necessary but
    // that would add complexity to the usage of these functions.
    // See https://github.com/bitcoin-dot-org/bitcoin.org/issues/580
    // Interpreting this value as a little endian uint256 lets us reverse it as soon as we read it.
    uint256 txHash = readUint256LE(txBytes, pos);
    pos += 32;
    uint32 txIndex = readUint32LE(txBytes, pos);
    pos += 4;

    return (txHash, txIndex, pos);
  }

  /**
   * Consumes all inputs in a transaction without storing anything in memory
   * @return index to tx output quantity var integer
   */
  function skipInputs(bytes memory txBytes, uint256 pos) private pure returns (uint256) {
    uint256 n_inputs;

    (n_inputs, pos) = parseVarInt(txBytes, pos);

    for (uint256 i = 0; i < n_inputs; i++) {
      // skip outpoint
      pos += 36;

      uint256 script_len;
      (script_len, pos) = parseVarInt(txBytes, pos);

      // skip sig_script and seq
      pos += script_len + 4;
    }

    return pos;
  }

  // similar to scanInputs, but consumes less gas since it doesn't store the inputs
  // also returns position of coinbase tx for later use
  function skipInputsAndGetScriptPos(
    bytes memory txBytes,
    uint256 pos,
    uint256 stop
  ) private pure returns (uint256, uint256) {
    uint256 script_pos;

    uint256 n_inputs;
    uint256 halt;
    uint256 script_len;

    (n_inputs, pos) = parseVarInt(txBytes, pos);

    if (stop == 0 || stop > n_inputs) {
      halt = n_inputs;
    } else {
      halt = stop;
    }

    for (uint256 i = 0; i < halt; i++) {
      pos += 36; // skip outpoint
      (script_len, pos) = parseVarInt(txBytes, pos);
      if (i == 0) script_pos = pos; // first input script begins where first script length ends
      // (script_len, pos) = (1, 0);
      pos += script_len + 4; // skip sig_script, seq
    }

    return (pos, script_pos);
  }

  // scan the outputs and find the values and script lengths.
  // return array of values, array of script lengths and the
  // end position of the outputs.
  // takes a 'stop' argument which sets the maximum number of
  // outputs to scan through. stop=0 => scan all.
  function scanOutputs(
    bytes memory txBytes,
    uint256 pos,
    uint256 stop
  )
    private
    pure
    returns (
      uint256[] memory,
      uint256[] memory,
      uint256[] memory,
      uint256
    )
  {
    uint256 n_outputs;
    uint256 halt;
    uint256 script_len;

    (n_outputs, pos) = parseVarInt(txBytes, pos);

    if (stop == 0 || stop > n_outputs) {
      halt = n_outputs;
    } else {
      halt = stop;
    }

    uint256[] memory script_starts = new uint256[](halt);
    uint256[] memory script_lens = new uint256[](halt);
    uint256[] memory output_values = new uint256[](halt);

    for (uint256 i = 0; i < halt; i++) {
      output_values[i] = readUint64LE(txBytes, pos);
      pos += 8;

      (script_len, pos) = parseVarInt(txBytes, pos);
      script_starts[i] = pos;
      script_lens[i] = script_len;
      pos += script_len;
    }

    return (output_values, script_starts, script_lens, pos);
  }

  // similar to scanOutputs, but consumes less gas since it doesn't store the outputs
  function skipOutputs(
    bytes memory txBytes,
    uint256 pos,
    uint256 stop
  ) private pure returns (uint256) {
    uint256 n_outputs;
    uint256 halt;
    uint256 script_len;

    (n_outputs, pos) = parseVarInt(txBytes, pos);

    if (stop == 0 || stop > n_outputs) {
      halt = n_outputs;
    } else {
      halt = stop;
    }

    for (uint256 i = 0; i < halt; i++) {
      pos += 8;

      (script_len, pos) = parseVarInt(txBytes, pos);
      pos += script_len;
    }

    return pos;
  }

  // get final position of inputs, outputs and lock time
  // this is a helper function to slice a byte array and hash the inputs, outputs and lock time
  function getSlicePosAndScriptPos(bytes memory txBytes, uint256 pos)
    private
    pure
    returns (uint256 slicePos, uint256 scriptPos)
  {
    (slicePos, scriptPos) = skipInputsAndGetScriptPos(txBytes, pos + 4, 0);
    slicePos = skipOutputs(txBytes, slicePos, 0);
    slicePos += 4; // skip lock time
  }

  // scan a Merkle branch.
  // return array of values and the end position of the sibling hashes.
  // takes a 'stop' argument which sets the maximum number of
  // siblings to scan through. stop=0 => scan all.
  function scanMerkleBranch(
    bytes memory txBytes,
    uint256 pos,
    uint256 stop
  ) private pure returns (uint256[] memory, uint256) {
    uint256 n_siblings;
    uint256 halt;

    (n_siblings, pos) = parseVarInt(txBytes, pos);

    if (stop == 0 || stop > n_siblings) {
      halt = n_siblings;
    } else {
      halt = stop;
    }

    uint256[] memory sibling_values = new uint256[](halt);

    for (uint256 i = 0; i < halt; i++) {
      sibling_values[i] = flip32Bytes(readUint256BE(txBytes, pos));
      pos += 32;
    }

    return (sibling_values, pos);
  }

  // Slice 20 contiguous bytes from bytes `data`, starting at `start`
  function sliceBytes20(bytes memory data, uint256 start) private pure returns (bytes20) {
    uint160 slice = 0;
    // FIXME: With solc v0.4.24 and optimizations enabled
    // using uint160 for index i will generate an error
    // "Error: VM Exception while processing transaction: Error: redPow(normalNum)"
    for (uint256 i = 0; i < 20; i++) {
      slice += uint160(uint8(data[i + start])) << uint160(8 * (19 - i));
    }
    return bytes20(slice);
  }

  // @dev returns a portion of a given byte array specified by its starting and ending points
  // Should be private, made internal for testing
  //
  // @param rawBytes - array to be sliced
  // @param offset - first byte of sliced array
  // @param endIndex - last byte of sliced array
  function sliceArray(
    bytes memory rawBytes,
    uint256 offset,
    uint256 endIndex
  ) internal view returns (bytes memory) {
    uint256 len = endIndex - offset;
    bytes memory result = new bytes(len);
    assembly {
      // Call precompiled contract to copy data
      if iszero(
        staticcall(gas(), 0x04, add(add(rawBytes, 0x20), offset), len, add(result, 0x20), len)
      ) {
        revert(0, 0)
      }
    }
    return result;
  }

  // returns true if the bytes located in txBytes by pos and
  // script_len represent a P2PKH script
  function isP2PKH(
    bytes memory txBytes,
    uint256 pos,
    uint256 script_len
  ) private pure returns (bool) {
    return
      (script_len == 25) && // 20 byte pubkeyhash + 5 bytes of script
      (txBytes[pos] == 0x76) && // OP_DUP
      (txBytes[pos + 1] == 0xa9) && // OP_HASH160
      (uint8(txBytes[pos + 2]) == 20) && // bytes to push
      (txBytes[pos + 23] == 0x88) && // OP_EQUALVERIFY
      (txBytes[pos + 24] == 0xac); // OP_CHECKSIG
  }

  // Get the pubkeyhash from an output script. Assumes
  // pay-to-pubkey-hash (P2PKH) outputs.
  // Returns the pubkeyhash, or zero if unknown output.
  function parseP2PKHOutputScript(
    bytes memory txBytes,
    uint256 pos,
    uint256 script_len
  ) private pure returns (bytes20) {
    require(isP2PKH(txBytes, pos, script_len), "Expected a P2PKH script in output.");
    return sliceBytes20(txBytes, pos + 3);
  }

  // Extract a signature
  function parseSignature(bytes memory txBytes, uint256 pos)
    private
    pure
    returns (bytes memory, uint256)
  {
    uint8 op;
    bytes memory sig;
    (op, pos) = getOpcode(txBytes, pos);
    require(op >= 9 && op <= 73);
    require(uint8(txBytes[pos]) == 0x30);
    //FIXME: Copy signature
    pos += op;
    return (sig, pos);
  }

  // Extract public key
  function parsePubKey(bytes memory txBytes, uint256 pos)
    private
    pure
    returns (
      bytes32,
      bool,
      uint256
    )
  {
    uint8 op;
    (op, pos) = getOpcode(txBytes, pos);
    //FIXME: Add support for uncompressed public keys
    require(op == 33, "Expected a compressed public key");
    bytes32 pubKey;
    bool odd = txBytes[pos] == 0x03;
    pos += 1;
    assembly {
      pubKey := mload(add(add(txBytes, 0x20), pos))
    }
    pos += 32;
    return (pubKey, odd, pos);
  }

  /**
   * Returns true if the tx output is an embedded ethereum address
   * @param txBytes Buffer where the entire transaction is stored.
   * @param pos Index into the tx buffer where the script is stored.
   * @param len Size of the script in terms of bytes.
   */
  function isEthereumAddress(
    bytes memory txBytes,
    uint256 pos,
    uint256 len
  ) private pure returns (bool) {
    // scriptPub format for the ethereum address is
    // 0x6a OP_RETURN
    // 0x14 PUSH20
    // []   20 bytes of the ethereum address
    return len == 20 + 2 && txBytes[pos] == bytes1(0x6a) && txBytes[pos + 1] == bytes1(0x14);
  }

  // Read the ethereum address embedded in the tx output
  function readEthereumAddress(
    bytes memory txBytes,
    uint256 pos,
    uint256
  ) private pure returns (address) {
    uint256 data;
    assembly {
      data := mload(add(add(txBytes, 22), pos))
    }
    return address(uint160(data));
  }

  // Read next opcode from script
  function getOpcode(bytes memory txBytes, uint256 pos) private pure returns (uint8, uint256) {
    return (uint8(txBytes[pos]), pos + 1);
  }

  function expmod(
    uint256 base,
    uint256 e,
    uint256 m
  ) internal view returns (uint256 o) {
    assembly {
      // pointer to free memory
      let pos := mload(0x40)
      mstore(pos, 0x20) // Length of Base
      mstore(add(pos, 0x20), 0x20) // Length of Exponent
      mstore(add(pos, 0x40), 0x20) // Length of Modulus
      mstore(add(pos, 0x60), base) // Base
      mstore(add(pos, 0x80), e) // Exponent
      mstore(add(pos, 0xa0), m) // Modulus
      // call modexp precompile!
      if iszero(staticcall(gas(), 0x05, pos, 0xc0, pos, 0x20)) {
        revert(0, 0)
      }
      // data
      o := mload(pos)
    }
  }

  function pub2address(uint256 x, bool odd) internal view returns (address) {
    // First, uncompress pub key
    uint256 yy = mulmod(x, x, p);
    yy = mulmod(yy, x, p);
    yy = addmod(yy, 7, p);
    uint256 y = expmod(yy, q, p);
    if (((y & 1) == 1) != odd) {
      y = p - y;
    }
    require(yy == mulmod(y, y, p));
    // Now, with uncompressed x and y, create the address
    return address(uint160(uint256(keccak256(abi.encodePacked(x, y)))));
  }

  // Gets the public key hash given a public key
  function pub2PubKeyHash(bytes32 pub, bool odd) internal pure returns (bytes20) {
    bytes1 firstByte = odd ? bytes1(0x03) : bytes1(0x02);
    return ripemd160(abi.encodePacked(sha256(abi.encodePacked(firstByte, pub))));
  }

  /**
   * @dev - convert an unsigned integer from little-endian to big-endian representation or viceversa
   *
   * @param input Little-endian value
   * @return result Input value in big-endian format
   */
  function flip32Bytes(uint256 input) internal pure returns (uint256 result) {
    assembly {
      let pos := mload(0x40)
      for {
        let i := 0
      } lt(i, 32) {
        i := add(i, 1)
      } {
        mstore8(add(pos, i), byte(sub(31, i), input))
      }
      result := mload(pos)
    }
  }

  // @dev - Parses AuxPow part of block header
  // @param rawBytes - array of bytes with the block header
  // @param pos - starting position of the block header
  // @param uint - length of the block header
  // @return auxpow - AuxPoW struct with parsed data
  function parseAuxPoW(
    bytes memory rawBytes,
    uint256 pos,
    uint256
  ) internal view returns (AuxPoW memory auxpow) {
    // we need to traverse the bytes with a pointer because some fields are of variable length
    pos += 80; // skip non-AuxPoW header
    // auxpow.firstBytes = readUint256BE(rawBytes, pos);
    uint256 slicePos;
    uint256 inputScriptPos;
    (slicePos, inputScriptPos) = getSlicePosAndScriptPos(rawBytes, pos);
    auxpow.txHash = dblShaFlipMem(rawBytes, pos, slicePos - pos);
    pos = slicePos;
    auxpow.scryptHash = readUint256BE(rawBytes, pos);
    pos += 32;
    (auxpow.parentMerkleProof, pos) = scanMerkleBranch(rawBytes, pos, 0);
    auxpow.coinbaseTxIndex = readUint32LE(rawBytes, pos);
    pos += 4;
    (auxpow.chainMerkleProof, pos) = scanMerkleBranch(rawBytes, pos, 0);
    auxpow.dogeHashIndex = readUint32LE(rawBytes, pos);
    pos += 40; // skip hash that was just read, parent version and prev block
    auxpow.parentMerkleRoot = readUint256BE(rawBytes, pos);
    pos += 40; // skip root that was just read, parent block timestamp and bits
    auxpow.parentNonce = readUint32LE(rawBytes, pos);
    uint256 coinbaseMerkleRootPosition;
    (
      auxpow.coinbaseMerkleRoot,
      coinbaseMerkleRootPosition,
      auxpow.coinbaseMerkleRootCode
    ) = findCoinbaseMerkleRoot(rawBytes);
    if (coinbaseMerkleRootPosition - inputScriptPos > 20 && auxpow.coinbaseMerkleRootCode == 1) {
      // if it was found once and only once but not in the first 20 bytes, return this error code
      auxpow.coinbaseMerkleRootCode = ERR_NOT_IN_FIRST_20;
    }
  }

  // @dev - looks for {0xfa, 0xbe, 'm', 'm'} byte sequence
  // returns the following 32 bytes if it appears once and only once,
  // 0 otherwise
  // also returns the position where the bytes first appear
  function findCoinbaseMerkleRoot(bytes memory rawBytes)
    private
    pure
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    uint256 position;
    bool found = false;

    for (uint256 i = 0; i < rawBytes.length; ++i) {
      if (
        rawBytes[i] == 0xfa &&
        rawBytes[i + 1] == 0xbe &&
        rawBytes[i + 2] == 0x6d &&
        rawBytes[i + 3] == 0x6d
      ) {
        if (found) {
          // found twice
          return (0, position - 4, ERR_FOUND_TWICE);
        } else {
          found = true;
          position = i + 4;
        }
      }
    }

    if (!found) {
      // no merge mining header
      return (0, position - 4, ERR_NO_MERGE_HEADER);
    } else {
      return (readUint256BE(rawBytes, position), position - 4, 1);
    }
  }

  // @dev - Evaluate the merkle root
  //
  // Given an array of hashes it calculates the
  // root of the merkle tree.
  //
  // @return root of merkle tree
  function makeMerkle(bytes32[] calldata hashes2) external pure returns (bytes32) {
    bytes32[] memory hashes = hashes2;
    uint256 length = hashes.length;
    if (length == 1) return hashes[0];
    require(length > 0);
    uint256 i;
    uint256 j;
    uint256 k;
    k = 0;
    while (length > 1) {
      k = 0;
      for (i = 0; i < length; i += 2) {
        j = i + 1 < length ? i + 1 : length - 1;
        hashes[k] = bytes32(concatHash(uint256(hashes[i]), uint256(hashes[j])));
        k += 1;
      }
      length = k;
    }
    return hashes[0];
  }

  // @dev - For a valid proof, returns the root of the Merkle tree.
  //
  // @param txHash - transaction hash
  // @param txIndex - transaction's index within the block it's assumed to be in
  // @param siblings - transaction's Merkle siblings
  // @return - Merkle tree root of the block the transaction belongs to if the proof is valid,
  // garbage if it's invalid
  function computeMerkle(
    uint256 txHash,
    uint256 txIndex,
    uint256[] memory siblings
  ) internal pure returns (uint256) {
    uint256 resultHash = txHash;
    for (uint256 i = 0; i < siblings.length; i++) {
      uint256 proofStep = siblings[i];

      uint256 left;
      uint256 right;
      // 0 means siblings is on the right; 1 means left
      if (txIndex % 2 == 1) {
        left = proofStep;
        right = resultHash;
      } else {
        left = resultHash;
        right = proofStep;
      }

      resultHash = concatHash(left, right);

      txIndex /= 2;
    }

    return resultHash;
  }

  // @dev - calculates the Merkle root of a tree containing Litecoin transactions
  // in order to prove that `ap`'s coinbase tx is in that Litecoin block.
  //
  // @param auxPow - AuxPoW information
  // @return - Merkle root of Litecoin block that the Dogecoin block
  // with this info was mined in if AuxPoW Merkle proof is correct,
  // garbage otherwise
  function computeParentMerkle(AuxPoW memory auxPow) internal pure returns (uint256) {
    return
      flip32Bytes(computeMerkle(auxPow.txHash, auxPow.coinbaseTxIndex, auxPow.parentMerkleProof));
  }

  // @dev - calculates the Merkle root of a tree containing auxiliary block hashes
  // in order to prove that the Dogecoin block identified by blockHash
  // was merge-mined in a Litecoin block.
  //
  // @param blockHash - SHA-256 hash of a certain Dogecoin block
  // @param auxPow - AuxPoW information corresponding to said block
  // @return - Merkle root of auxiliary chain tree
  // if AuxPoW Merkle proof is correct, garbage otherwise
  function computeChainMerkle(uint256 blockHash, AuxPoW memory auxPow)
    internal
    pure
    returns (uint256)
  {
    return computeMerkle(blockHash, auxPow.dogeHashIndex, auxPow.chainMerkleProof);
  }

  // @dev - Helper function for Merkle root calculation.
  // Given two sibling nodes in a Merkle tree, calculate their parent.
  // Concatenates hashes `tx1` and `tx2`, then hashes the result.
  //
  // @param tx1 - Merkle node (either root or internal node)
  // @param tx2 - Merkle node (either root or internal node), has to be `tx1`'s sibling
  // @return - `tx1` and `tx2`'s parent, i.e. the result of concatenating them,
  // hashing that twice and flipping the bytes.
  function concatHash(uint256 tx1, uint256 tx2) internal pure returns (uint256) {
    return
      flip32Bytes(
        uint256(
          sha256(abi.encodePacked(sha256(abi.encodePacked(flip32Bytes(tx1), flip32Bytes(tx2)))))
        )
      );
  }

  // @dev - checks if a merge-mined block's Merkle proofs are correct,
  // i.e. Doge block hash is in coinbase Merkle tree
  // and coinbase transaction is in parent Merkle tree.
  //
  // @param blockHash - SHA-256 hash of the block whose Merkle proofs are being checked
  // @param auxPow - AuxPoW struct corresponding to the block
  // @return 1 if block was merge-mined and coinbase index, chain Merkle root and Merkle proofs are correct,
  // respective error code otherwise
  function checkAuxPoW(uint256 blockHash, AuxPoW memory auxPow) internal pure returns (uint256) {
    if (auxPow.coinbaseTxIndex != 0) {
      return ERR_COINBASE_INDEX;
    }

    if (auxPow.coinbaseMerkleRootCode != 1) {
      return auxPow.coinbaseMerkleRootCode;
    }

    if (computeChainMerkle(blockHash, auxPow) != auxPow.coinbaseMerkleRoot) {
      return ERR_CHAIN_MERKLE;
    }

    if (computeParentMerkle(auxPow) != auxPow.parentMerkleRoot) {
      return ERR_PARENT_MERKLE;
    }

    return 1;
  }

  function sha256mem(
    bytes memory rawBytes,
    uint256 offset,
    uint256 len
  ) internal view returns (bytes32 result) {
    assembly {
      // Call sha256 precompiled contract (located in address 0x02) to copy data.
      // Assign to pos the next available memory position (stored in memory position 0x40).
      let pos := mload(0x40)
      if iszero(staticcall(gas(), 0x02, add(add(rawBytes, 0x20), offset), len, pos, 0x20)) {
        revert(0, 0)
      }
      result := mload(pos)
    }
  }

  // @dev - Bitcoin-way of hashing
  // @param dataBytes - raw data to be hashed
  // @return - result of applying SHA-256 twice to raw data and then flipping the bytes
  function dblShaFlip(bytes memory dataBytes) internal pure returns (uint256) {
    return flip32Bytes(uint256(sha256(abi.encodePacked(sha256(abi.encodePacked(dataBytes))))));
  }

  // @dev - Bitcoin-way of hashing
  // @param dataBytes - raw data to be hashed
  // @return - result of applying SHA-256 twice to raw data and then flipping the bytes
  function dblShaFlipMem(
    bytes memory rawBytes,
    uint256 offset,
    uint256 len
  ) internal view returns (uint256) {
    return flip32Bytes(uint256(sha256(abi.encodePacked(sha256mem(rawBytes, offset, len)))));
  }

  // @dev – Read a bytes32 from an offset in the byte array
  function readBytes32(bytes memory data, uint256 offset) internal pure returns (bytes32) {
    bytes32 result;
    assembly {
      result := mload(add(add(data, 0x20), offset))
    }
    return result;
  }

  // @dev – Read an uint32 from an offset in the byte array
  function readUint32(bytes memory data, uint256 offset) internal pure returns (uint32) {
    uint32 result;
    assembly {
      let word := mload(add(add(data, 0x20), offset))
      result := add(
        byte(3, word),
        add(
          mul(byte(2, word), 0x100),
          add(mul(byte(1, word), 0x10000), mul(byte(0, word), 0x1000000))
        )
      )
    }
    return result;
  }

  // @dev - Bitcoin-way of computing the target from the 'bits' field of a block header
  // based on http://www.righto.com/2014/02/bitcoin-mining-hard-way-algorithms.html//ref3
  //
  // @param bits - difficulty in bits format
  // @return - difficulty in target format
  function targetFromBits(uint32 bits) internal pure returns (uint256) {
    uint256 exp = bits / 0x1000000; // 2**24
    uint256 mant = bits & 0xffffff;
    return mant * 256**(exp - 3);
  }

  uint256 constant DOGECOIN_DIFFICULTY_ONE = 0xFFFFF * 256**(0x1e - 3);

  // @dev - Calculate dogecoin difficulty from target
  // https://en.bitcoin.it/wiki/Difficulty
  // Min difficulty for bitcoin is 0x1d00ffff
  // Min difficulty for dogecoin is 0x1e0fffff
  function targetToDiff(uint256 target) internal pure returns (uint256) {
    return DOGECOIN_DIFFICULTY_ONE / target;
  }

  // @dev - Parse an array of bytes32
  function parseBytes32Array(bytes calldata data) external pure returns (bytes32[] memory) {
    require(data.length % 32 == 0);
    uint256 count = data.length / 32;
    bytes32[] memory hashes = new bytes32[](count);
    for (uint256 i = 0; i < count; ++i) {
      hashes[i] = readBytes32(data, 32 * i);
    }
    return hashes;
  }

  // 0x00 version
  // 0x04 prev block hash
  // 0x24 merkle root
  // 0x44 timestamp
  // 0x48 bits
  // 0x4c nonce

  // @dev - extract version field from a raw Dogecoin block header
  //
  // @param blockHeader - Dogecoin block header bytes
  // @param pos - where to start reading version from
  // @return - block's version in big endian format
  function getVersion(bytes memory blockHeader, uint256 pos)
    internal
    pure
    returns (uint32 version)
  {
    assembly {
      let word := mload(add(add(blockHeader, 0x4), pos))
      version := add(
        byte(24, word),
        add(
          mul(byte(25, word), 0x100),
          add(mul(byte(26, word), 0x10000), mul(byte(27, word), 0x1000000))
        )
      )
    }
  }

  // @dev - extract previous block field from a raw Dogecoin block header
  //
  // @param blockHeader - Dogecoin block header bytes
  // @param pos - where to start reading hash from
  // @return - hash of block's parent in big endian format
  function getHashPrevBlock(bytes memory blockHeader, uint256 pos) internal pure returns (uint256) {
    uint256 hashPrevBlock;
    assembly {
      hashPrevBlock := mload(add(add(blockHeader, 0x24), pos))
    }
    return flip32Bytes(hashPrevBlock);
  }

  // @dev - extract Merkle root field from a raw Dogecoin block header
  //
  // @param blockHeader - Dogecoin block header bytes
  // @param pos - where to start reading root from
  // @return - block's Merkle root in big endian format
  function getHeaderMerkleRoot(bytes memory blockHeader, uint256 pos)
    public
    pure
    returns (uint256)
  {
    uint256 merkle;
    assembly {
      merkle := mload(add(add(blockHeader, 0x44), pos))
    }
    return flip32Bytes(merkle);
  }

  // @dev - extract bits field from a raw Dogecoin block header
  //
  // @param blockHeader - Dogecoin block header bytes
  // @param pos - where to start reading bits from
  // @return - block's difficulty in bits format, also big-endian
  function getBits(bytes memory blockHeader, uint256 pos) internal pure returns (uint32 bits) {
    assembly {
      let word := mload(add(add(blockHeader, 0x50), pos))
      bits := add(
        byte(24, word),
        add(
          mul(byte(25, word), 0x100),
          add(mul(byte(26, word), 0x10000), mul(byte(27, word), 0x1000000))
        )
      )
    }
  }

  // @dev - extract timestamp field from a raw Dogecoin block header
  //
  // @param blockHeader - Dogecoin block header bytes
  // @param pos - where to start reading bits from
  // @return - block's timestamp in big-endian format
  function getTimestamp(bytes memory blockHeader, uint256 pos) internal pure returns (uint32 time) {
    assembly {
      let word := mload(add(add(blockHeader, 0x4c), pos))
      time := add(
        byte(24, word),
        add(
          mul(byte(25, word), 0x100),
          add(mul(byte(26, word), 0x10000), mul(byte(27, word), 0x1000000))
        )
      )
    }
  }

  // @dev - converts raw bytes representation of a Dogecoin block header to struct representation
  //
  // @param rawBytes - first 80 bytes of a block header
  // @return - exact same header information in BlockHeader struct form
  function parseHeaderBytes(bytes memory rawBytes, uint256 pos)
    internal
    view
    returns (BlockHeader memory bh)
  {
    bh.version = getVersion(rawBytes, pos);
    bh.time = getTimestamp(rawBytes, pos);
    bh.bits = getBits(rawBytes, pos);
    bh.blockHash = dblShaFlipMem(rawBytes, pos, 80);
    bh.prevBlock = getHashPrevBlock(rawBytes, pos);
    bh.merkleRoot = getHeaderMerkleRoot(rawBytes, pos);
  }

  uint32 constant VERSION_AUXPOW = (1 << 8);

  // @dev - Converts a bytes of size 4 to uint32,
  // e.g. for input [0x01, 0x02, 0x03 0x04] returns 0x01020304
  function bytesToUint32Flipped(bytes memory input, uint256 pos)
    internal
    pure
    returns (uint32 result)
  {
    result =
      uint32(uint8(input[pos])) +
      uint32(uint8(input[pos + 1])) *
      (2**8) +
      uint32(uint8(input[pos + 2])) *
      (2**16) +
      uint32(uint8(input[pos + 3])) *
      (2**24);
  }

  // @dev - checks version to determine if a block has merge mining information
  function isMergeMined(bytes memory rawBytes, uint256 pos) internal pure returns (bool) {
    return bytesToUint32Flipped(rawBytes, pos) & VERSION_AUXPOW != 0;
  }

  // @dev - checks version to determine if a block has merge mining information
  function isMergeMined(BlockHeader memory blockHeader) internal pure returns (bool) {
    return blockHeader.version & VERSION_AUXPOW != 0;
  }

  // @dev - Verify block header
  // @param blockHeaderBytes - array of bytes with the block header
  // @param pos - starting position of the block header
  // @param len - length of the block header
  // @param proposedBlockScryptHash - proposed block scrypt hash
  // @return - [ErrorCode, BlockSha256Hash, BlockScryptHash, IsMergeMined]
  function verifyBlockHeader(
    bytes calldata blockHeaderBytes,
    uint256 pos,
    uint256 len,
    uint256 proposedBlockScryptHash
  )
    external
    view
    returns (
      uint256,
      uint256,
      uint256,
      bool
    )
  {
    BlockHeader memory blockHeader = parseHeaderBytes(blockHeaderBytes, pos);
    uint256 blockSha256Hash = blockHeader.blockHash;
    if (isMergeMined(blockHeader)) {
      AuxPoW memory ap = parseAuxPoW(blockHeaderBytes, pos, len);
      if (flip32Bytes(ap.scryptHash) > targetFromBits(blockHeader.bits)) {
        return (ERR_PROOF_OF_WORK, blockHeader.blockHash, ap.scryptHash, true);
      }
      uint256 auxPoWCode = checkAuxPoW(blockSha256Hash, ap);
      if (auxPoWCode != 1) {
        return (auxPoWCode, blockHeader.blockHash, ap.scryptHash, true);
      }
      return (0, blockHeader.blockHash, ap.scryptHash, true);
    } else {
      if (flip32Bytes(proposedBlockScryptHash) > targetFromBits(blockHeader.bits)) {
        return (ERR_PROOF_OF_WORK, blockHeader.blockHash, proposedBlockScryptHash, false);
      }
      return (0, blockHeader.blockHash, proposedBlockScryptHash, false);
    }
  }

  // @dev - Calculate difficulty from compact representation (bits) found in block
  function diffFromBits(uint32 bits) external pure returns (uint256) {
    return targetToDiff(targetFromBits(bits));
  }

  // For verifying Dogecoin difficulty
  uint256 constant DIFFICULTY_ADJUSTMENT_INTERVAL = 1; // Bitcoin adjusts every block
  int64 constant TARGET_TIMESPAN = 60; // 1 minute
  int64 constant TARGET_TIMESPAN_DIV_4 = TARGET_TIMESPAN / 4;
  int64 constant TARGET_TIMESPAN_MUL_4 = TARGET_TIMESPAN * 4;
  uint256 constant UNROUNDED_MAX_TARGET = 2**224 - 1; // different from (2**16-1)*2**208 http =//bitcoin.stackexchange.com/questions/13803/how/ exactly-was-the-original-coefficient-for-difficulty-determined
  uint256 constant POW_LIMIT = 0x00000fffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

  // @dev - Implementation of DigiShield, almost directly translated from
  // C++ implementation of Dogecoin. See function calculateDogecoinNextWorkRequired
  // on dogecoin/src/dogecoin.cpp for more details.
  // Calculates the next block's difficulty based on the current block's elapsed time
  // and the desired mining time for a block, which is 60 seconds after block 145k.
  //
  // @param actualTimespan - time elapsed from previous block creation til current block creation;
  // i.e., how much time it took to mine the current block
  // @param bits - previous block header difficulty (in bits)
  // @return - expected difficulty for the next block
  function calculateDigishieldDifficulty(int64 actualTimespan, uint32 bits)
    external
    pure
    returns (uint32 result)
  {
    int64 retargetTimespan = int64(TARGET_TIMESPAN);
    int64 nModulatedTimespan = int64(actualTimespan);

    nModulatedTimespan = retargetTimespan + int64(nModulatedTimespan - retargetTimespan) / int64(8); //amplitude filter
    int64 nMinTimespan = retargetTimespan - (int64(retargetTimespan) / int64(4));
    int64 nMaxTimespan = retargetTimespan + (int64(retargetTimespan) / int64(2));

    // Limit adjustment step
    if (nModulatedTimespan < nMinTimespan) {
      nModulatedTimespan = nMinTimespan;
    } else if (nModulatedTimespan > nMaxTimespan) {
      nModulatedTimespan = nMaxTimespan;
    }

    // Retarget
    uint256 bnNew = targetFromBits(bits);
    bnNew = bnNew * uint64(nModulatedTimespan);
    bnNew = bnNew / uint64(retargetTimespan);

    if (bnNew > POW_LIMIT) {
      bnNew = POW_LIMIT;
    }

    return toCompactBits(bnNew);
  }

  // @dev - shift information to the right by a specified number of bits
  //
  // @param val - value to be shifted
  // @param shift - number of bits to shift
  // @return - `val` shifted `shift` bits to the right, i.e. divided by 2**`shift`
  function shiftRight(uint256 val, uint256 shift) private pure returns (uint256) {
    return val / uint256(2)**shift;
  }

  // @dev - shift information to the left by a specified number of bits
  //
  // @param val - value to be shifted
  // @param shift - number of bits to shift
  // @return - `val` shifted `shift` bits to the left, i.e. multiplied by 2**`shift`
  function shiftLeft(uint256 val, uint256 shift) private pure returns (uint256) {
    return val * uint256(2)**shift;
  }

  // @dev - get the number of bits required to represent a given integer value without losing information
  //
  // @param val - unsigned integer value
  // @return - given value's bit length
  function bitLen(uint256 val) private pure returns (uint256 length) {
    uint256 int_type = val;
    while (int_type > 0) {
      int_type = shiftRight(int_type, 1);
      length += 1;
    }
  }

  // @dev - Convert uint256 to compact encoding
  // based on https://github.com/petertodd/python-bitcoinlib/blob/2a5dda45b557515fb12a0a18e5dd48d2f5cd13c2/bitcoin/core/serialize.py
  // Analogous to arith_uint256::GetCompact from C++ implementation
  //
  // @param val - difficulty in target format
  // @return - difficulty in bits format
  function toCompactBits(uint256 val) private pure returns (uint32) {
    uint256 nbytes = uint256(shiftRight((bitLen(val) + 7), 3));
    uint32 compact = 0;
    if (nbytes <= 3) {
      compact = uint32(shiftLeft((val & 0xFFFFFF), 8 * (3 - nbytes)));
    } else {
      compact = uint32(shiftRight(val, 8 * (nbytes - 3)));
      compact = uint32(compact & 0xFFFFFF);
    }

    // If the sign bit (0x00800000) is set, divide the mantissa by 256 and
    // increase the exponent to get an encoding without it set.
    if ((compact & 0x00800000) > 0) {
      compact = uint32(shiftRight(compact, 8));
      nbytes += 1;
    }

    return compact | uint32(shiftLeft(nbytes, 24));
  }

  /**
   * Dead code.
   * This is currently unused code. This should be deleted once it is deemed no longer useful.
   * It is commented out to avoid code generation.
   */

  /*

    function getInputPubKey(bytes memory txBytes, InputDescriptor memory input) private pure
             returns (bytes32, bool)
    {
        bytes32 pubKey;
        bool odd;
        (, pubKey, odd,) = parseScriptSig(txBytes, input.sigScriptOffset);
        return (pubKey, odd);
    }

    // Parse a P2PKH scriptSig
    // TODO: add script length as a parameter?
    function parseScriptSig(bytes memory txBytes, uint pos) private pure
             returns (bytes memory, bytes32, bool, uint)
    {
        bytes memory sig;
        bytes32 pubKey;
        bool odd;
        // TODO: do we want the signature?
        (sig, pos) = parseSignature(txBytes, pos);
        (pubKey, odd, pos) = parsePubKey(txBytes, pos);
        return (sig, pubKey, odd, pos);
    }

    // Check whether `btcAddress` is in the transaction outputs *and*
    // whether *at least* `value` has been sent to it.
    function checkValueSent(bytes memory txBytes, bytes20 btcAddress, uint value) private pure
             returns (bool)
    {
        uint pos = TX_INPUTS_OFFSET;
        pos = skipInputs(txBytes, pos);  // find end of inputs

        // scan *all* the outputs and find where they are
        uint[] memory output_values;
        uint[] memory script_starts;
        uint[] memory output_script_lens;
        (output_values, script_starts, output_script_lens,) = scanOutputs(txBytes, pos, 0);

        // look at each output and check whether it at least value to btcAddress
        for (uint i = 0; i < output_values.length; i++) {
            bytes20 pkhash = parseOutputScript(txBytes, script_starts[i], output_script_lens[i]);
            if (pkhash == btcAddress && output_values[i] >= value) {
                return true;
            }
        }
        return false;
    }

    // Get the pubkeyhash / scripthash from an output script. Assumes
    // pay-to-pubkey-hash (P2PKH) or pay-to-script-hash (P2SH) outputs.
    // Returns the pubkeyhash/ scripthash, or zero if unknown output.
    function parseOutputScript(bytes memory txBytes, uint pos, uint script_len) private pure
             returns (bytes20)
    {
        if (isP2PKH(txBytes, pos, script_len)) {
            return sliceBytes20(txBytes, pos + 3);
        } else if (isP2SH(txBytes, pos, script_len)) {
            return sliceBytes20(txBytes, pos + 2);
        } else {
            return bytes20(0);
        }
    }

    // returns true if the bytes located in txBytes by pos and
    // script_len represent a P2SH script
    function isP2SH(bytes memory txBytes, uint pos, uint script_len) private pure returns (bool) {
        return (script_len == 23)           // 20 byte scripthash + 3 bytes of script
            && (txBytes[pos + 0] == 0xa9)   // OP_HASH160
            && (txBytes[pos + 1] == 0x14)   // bytes to push
            && (txBytes[pos + 22] == 0x87); // OP_EQUAL
    }

    // scan the full transaction bytes and return the first two output
    // values (in satoshis) and addresses (in binary)
    function getFirstTwoOutputs(bytes memory txBytes) internal pure
             returns (uint, bytes20, uint, bytes20)
    {
        uint pos;
        uint[] memory output_script_lens;
        uint[] memory script_starts;
        uint[] memory output_values;
        bytes20[] memory output_public_key_hashes = new bytes20[](2);

        pos = TX_INPUTS_OFFSET;

        pos = skipInputs(txBytes, pos);

        (output_values, script_starts, output_script_lens, pos) = scanOutputs(txBytes, pos, 2);

        for (uint i = 0; i < 2; i++) {
            bytes20 pkhash = parseP2PKHOutputScript(txBytes, script_starts[i], output_script_lens[i]);
            output_public_key_hashes[i] = pkhash;
        }

        return (output_values[0], output_public_key_hashes[0],
                output_values[1], output_public_key_hashes[1]);
    }

    // helpers for flip32Bytes
    struct UintWrapper {
        uint value;
    }

    function ptr(UintWrapper memory uw) private pure returns (uint addr) {
        assembly {
            addr := uw
        }
    }

    */
}

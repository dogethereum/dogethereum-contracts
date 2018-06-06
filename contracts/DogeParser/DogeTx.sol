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

pragma solidity ^0.4.19;

// parse a raw bitcoin transaction byte array
library DogeTx {

    uint constant p = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f;  // secp256k1
    uint constant q = (p + 1) / 4;

    // Error codes
    uint constant ERR_INVALID_HEADER = 10050;
    uint constant ERR_COINBASE_INDEX = 10060; // coinbase tx index within Litecoin merkle isn't 0
    uint constant ERR_NOT_MERGE_MINED = 10070; // trying to check AuxPoW on a block that wasn't merge mined
    uint constant ERR_FOUND_TWICE = 10080; // 0xfabe6d6d found twice
    uint constant ERR_NO_MERGE_HEADER = 10090; // 0xfabe6d6d not found
    uint constant ERR_NOT_IN_FIRST_20 = 10100; // chain Merkle root isn't in the first 20 bytes of coinbase tx
    uint constant ERR_CHAIN_MERKLE = 10110;
    uint constant ERR_PARENT_MERKLE = 10120;
    uint constant ERR_PROOF_OF_WORK = 10130;

    // AuxPoW block fields
    struct AuxPoW {
        // uint firstBytes;

        uint scryptHash;

        uint txHash;

        uint coinbaseMerkleRoot; // Merkle root of auxiliary block hash tree; stored in coinbase tx field
        uint[] chainMerkleProof; // proves that a given Dogecoin block hash belongs to a tree with the above root
        uint dogeHashIndex; // index of Doge block hash within block hash tree
        uint coinbaseMerkleRootCode; // encodes whether or not the root was found properly

        uint parentMerkleRoot; // Merkle root of transaction tree from parent Litecoin block header
        uint[] parentMerkleProof; // proves that coinbase tx belongs to a tree with the above root
        uint coinbaseTxIndex; // index of coinbase tx within Litecoin tx tree

        uint parentNonce;
    }

    // Dogecoin block header stored as a struct, mostly for readability purposes.
    // BlockHeader structs can be obtained by parsing a block header's first 80 bytes
    // with parseHeaderBytes.
    struct BlockHeader {
        uint32 version;
        uint32 time;
        uint32 bits;
        uint32 nonce;
        uint blockHash;
        uint prevBlock;
        uint merkleRoot;
    }

    // Convert a variable integer into something useful and return it and
    // the index to after it.
    function parseVarInt(bytes txBytes, uint pos) private pure returns (uint, uint) {
        // the first byte tells us how big the integer is
        uint8 ibit = uint8(txBytes[pos]);
        pos += 1;  // skip ibit

        if (ibit < 0xfd) {
            return (ibit, pos);
        } else if (ibit == 0xfd) {
            return (getBytesLE(txBytes, pos, 16), pos + 2);
        } else if (ibit == 0xfe) {
            return (getBytesLE(txBytes, pos, 32), pos + 4);
        } else if (ibit == 0xff) {
            return (getBytesLE(txBytes, pos, 64), pos + 8);
        }
    }
    // convert little endian bytes to uint
    function getBytesLE(bytes data, uint pos, uint bits) internal pure returns (uint) {
        if (bits == 8) {
            return uint8(data[pos]);
        } else if (bits == 16) {
            return uint16(data[pos])
                 + uint16(data[pos + 1]) * 2 ** 8;
        } else if (bits == 32) {
            return uint32(data[pos])
                 + uint32(data[pos + 1]) * 2 ** 8
                 + uint32(data[pos + 2]) * 2 ** 16
                 + uint32(data[pos + 3]) * 2 ** 24;
        } else if (bits == 64) {
            return uint64(data[pos])
                 + uint64(data[pos + 1]) * 2 ** 8
                 + uint64(data[pos + 2]) * 2 ** 16
                 + uint64(data[pos + 3]) * 2 ** 24
                 + uint64(data[pos + 4]) * 2 ** 32
                 + uint64(data[pos + 5]) * 2 ** 40
                 + uint64(data[pos + 6]) * 2 ** 48
                 + uint64(data[pos + 7]) * 2 ** 56;
        }
    }

    struct ParseTransactionVariablesStruct {
        uint pos;
        bytes20 output_public_key_hash;
        uint output_value;
        uint16 outputIndex;
        bytes32 inputPubKey;
        bool inputPubKeyOdd;
    }

    // Parses a doge tx
    // Inputs
    // txBytes: tx byte array
    // expected_output_public_key_hash: lock address (actually, it's public key hash expected to be on 1st or 2nd output, require() fails otherwise)
    // Outputs
    // output_value: amount sent to the lock address in satoshis
    // inputPubKey: "x" axis value of the public key used to sign the first output
    // inputPubKeyOdd: Indicates inputPubKey odd bit
    // outputIndex: number of output where expected_output_address was found

    function parseTransaction(bytes txBytes, bytes20 expected_output_public_key_hash) internal pure
             returns (uint, bytes32, bool, uint16)
    {
        ParseTransactionVariablesStruct memory variables;
        uint[] memory input_script_lens;
        uint[] memory input_script_starts;
        uint[] memory output_script_lens;
        uint[] memory output_script_starts;
        uint[] memory output_values;

        variables.pos = 4;  // skip version
        (input_script_starts, input_script_lens, variables.pos) = scanInputs(txBytes, variables.pos, 0);

        (variables.inputPubKey, variables.inputPubKeyOdd) = getInputPubKey(txBytes, input_script_starts[0]);

        (output_values, output_script_starts, output_script_lens, variables.pos) = scanOutputs(txBytes, variables.pos, 2);
        // The output we are looking for should be the first or the second output
        variables.output_public_key_hash = parseP2PKHOutputScript(txBytes, output_script_starts[0], output_script_lens[0]);
        variables.output_value = output_values[0];
        variables.outputIndex = 0;

        if (variables.output_public_key_hash != expected_output_public_key_hash) {
            variables.output_public_key_hash = parseP2PKHOutputScript(txBytes, output_script_starts[1], output_script_lens[1]);
            variables.output_value = output_values[1];
            variables.outputIndex = 1;
        }
        require(variables.output_public_key_hash == expected_output_public_key_hash);

        return (variables.output_value, variables.inputPubKey, variables.inputPubKeyOdd, variables.outputIndex);
    }

    // scan the full transaction bytes and return the first two output
    // values (in satoshis) and addresses (in binary)
    function getFirstTwoOutputs(bytes txBytes) internal pure
             returns (uint, bytes20, uint, bytes20)
    {
        uint pos;
        uint[] memory input_script_lens;
        uint[] memory output_script_lens;
        uint[] memory script_starts;
        uint[] memory output_values;
        bytes20[] memory output_public_key_hashes = new bytes20[](2);

        pos = 4;  // skip version

        (, input_script_lens, pos) = scanInputs(txBytes, pos, 0);

        (output_values, script_starts, output_script_lens, pos) = scanOutputs(txBytes, pos, 2);

        for (uint i = 0; i < 2; i++) {
            bytes20 pkhash = parseP2PKHOutputScript(txBytes, script_starts[i], output_script_lens[i]);
            output_public_key_hashes[i] = pkhash;
        }

        return (output_values[0], output_public_key_hashes[0],
                output_values[1], output_public_key_hashes[1]);
    }

    function getFirstInputPubKey(bytes txBytes) private pure
             returns (bytes32, bool)
    {
        uint pos;
        uint[] memory input_script_lens;
        // The line above fires a warning because the variable hasn't been used.
        // It's probably NOT a good idea to comment it until the function is more or less finished because the warning could be useful for debugging.

        pos = 4;  // skip version

        (, pos) = parseVarInt(txBytes, pos);
        return getInputPubKey(txBytes, pos);
    }

    function getInputPubKey(bytes txBytes, uint pos) private pure
             returns (bytes32, bool)
    {
        pos += 36;  // skip outpoint
        (, pos) = parseVarInt(txBytes, pos);
        bytes32 pubKey;
        bool odd;
        (, pubKey, odd, pos) = parseScriptSig(txBytes, pos);
        return (pubKey, odd);
    }

    // Check whether `btcAddress` is in the transaction outputs *and*
    // whether *at least* `value` has been sent to it.
    function checkValueSent(bytes txBytes, bytes20 btcAddress, uint value) private pure
             returns (bool)
    {
        uint pos = 4;  // skip version
        (,, pos) = scanInputs(txBytes, pos, 0);  // find end of inputs

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
    }
    // scan the inputs and find the script lengths.
    // return an array of script lengths and the end position
    // of the inputs.
    // takes a 'stop' argument which sets the maximum number of
    // outputs to scan through. stop=0 => scan all.
    function scanInputs(bytes txBytes, uint pos, uint stop) private pure
             returns (uint[], uint[], uint)
    {
        uint n_inputs;
        uint halt;
        uint script_len;

        (n_inputs, pos) = parseVarInt(txBytes, pos);

        if (stop == 0 || stop > n_inputs) {
            halt = n_inputs;
        } else {
            halt = stop;
        }

        uint[] memory script_starts = new uint[](halt);
        uint[] memory script_lens = new uint[](halt);

        for (uint256 i = 0; i < halt; i++) {
            script_starts[i] = pos;
            pos += 36;  // skip outpoint
            (script_len, pos) = parseVarInt(txBytes, pos);
            script_lens[i] = script_len;
            pos += script_len + 4;  // skip sig_script, seq
        }

        return (script_starts, script_lens, pos);
    }
    // similar to scanInputs, but consumes less gas since it doesn't store the inputs
    // also returns position of coinbase tx for later use
    function skipInputsAndGetScriptPos(bytes txBytes, uint pos, uint stop) private pure
             returns (uint, uint)
    {
        uint script_pos;

        uint n_inputs;
        uint halt;
        uint script_len;

        (n_inputs, pos) = parseVarInt(txBytes, pos);

        if (stop == 0 || stop > n_inputs) {
            halt = n_inputs;
        } else {
            halt = stop;
        }

        for (uint256 i = 0; i < halt; i++) {
            pos += 36;  // skip outpoint
            (script_len, pos) = parseVarInt(txBytes, pos);
            if (i == 0)
                script_pos = pos; // first input script begins where first script length ends
            // (script_len, pos) = (1, 0);
            pos += script_len + 4;  // skip sig_script, seq
        }

        return (pos, script_pos);
    }
    // scan the outputs and find the values and script lengths.
    // return array of values, array of script lengths and the
    // end position of the outputs.
    // takes a 'stop' argument which sets the maximum number of
    // outputs to scan through. stop=0 => scan all.
    function scanOutputs(bytes txBytes, uint pos, uint stop) private pure
             returns (uint[], uint[], uint[], uint)
    {
        uint n_outputs;
        uint halt;
        uint script_len;

        (n_outputs, pos) = parseVarInt(txBytes, pos);

        if (stop == 0 || stop > n_outputs) {
            halt = n_outputs;
        } else {
            halt = stop;
        }

        uint[] memory script_starts = new uint[](halt);
        uint[] memory script_lens = new uint[](halt);
        uint[] memory output_values = new uint[](halt);

        for (uint256 i = 0; i < halt; i++) {
            output_values[i] = getBytesLE(txBytes, pos, 64);
            pos += 8;

            (script_len, pos) = parseVarInt(txBytes, pos);
            script_starts[i] = pos;
            script_lens[i] = script_len;
            pos += script_len;
        }

        return (output_values, script_starts, script_lens, pos);
    }
    // similar to scanOutputs, but consumes less gas since it doesn't store the outputs
    function skipOutputs(bytes txBytes, uint pos, uint stop) private pure
             returns (uint)
    {
        uint n_outputs;
        uint halt;
        uint script_len;

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
    function getSlicePosAndScriptPos(bytes txBytes, uint pos) private pure
             returns (uint slicePos, uint scriptPos)
    {
        (slicePos, scriptPos) = skipInputsAndGetScriptPos(txBytes, pos + 4, 0);
        slicePos = skipOutputs(txBytes, slicePos, 0);
        slicePos += 4; // skip lock time
    }
    // scan a Merkle branch.
    // return array of values and the end position of the sibling hashes.
    // takes a 'stop' argument which sets the maximum number of
    // siblings to scan through. stop=0 => scan all.
    function scanMerkleBranch(bytes txBytes, uint pos, uint stop) private pure
             returns (uint[], uint)
    {
        uint n_siblings;
        uint halt;

        (n_siblings, pos) = parseVarInt(txBytes, pos);

        if (stop == 0 || stop > n_siblings) {
            halt = n_siblings;
        } else {
            halt = stop;
        }

        uint[] memory sibling_values = new uint[](halt);

        for (uint256 i = 0; i < halt; i++) {
            sibling_values[i] = flip32Bytes(sliceBytes32Int(txBytes, pos));
            pos += 32;
        }

        return (sibling_values, pos);
    }
    // Slice 20 contiguous bytes from bytes `data`, starting at `start`
    function sliceBytes20(bytes data, uint start) private pure returns (bytes20) {
        uint160 slice = 0;
        for (uint160 i = 0; i < 20; i++) {
            slice += uint160(data[i + start]) << (8 * (19 - i));
        }
        return bytes20(slice);
    }
    // Slice 32 contiguous bytes from bytes `data`, starting at `start`
    function sliceBytes32Int(bytes data, uint start) private pure returns (uint slice) {
        for (uint i = 0; i < 32; i++) {
            if (i + start < data.length) {
                slice += uint(data[i + start]) << (8 * (31 - i));
            }
        }
    }

    // @dev returns a portion of a given byte array specified by its starting and ending points
    // Should be private, made internal for testing
    // Breaks underscore naming convention for parameters because it raises a compiler error
    // if `offset` is changed to `_offset`.
    //
    // @param _rawBytes - array to be sliced
    // @param offset - first byte of sliced array
    // @param _endIndex - last byte of sliced array
    function sliceArray(bytes memory _rawBytes, uint offset, uint _endIndex) internal view returns (bytes) {
        uint len = _endIndex - offset;
        bytes memory result = new bytes(len);
        assembly {
            // Call precompiled contract to copy data
            if iszero(staticcall(gas, 0x04, add(add(_rawBytes, 0x20), offset), len, add(result, 0x20), len)) {
                revert(0, 0)
            }
        }
        return result;
    }
    // returns true if the bytes located in txBytes by pos and
    // script_len represent a P2PKH script
    function isP2PKH(bytes txBytes, uint pos, uint script_len) private pure returns (bool) {
        return (script_len == 25)           // 20 byte pubkeyhash + 5 bytes of script
            && (txBytes[pos] == 0x76)       // OP_DUP
            && (txBytes[pos + 1] == 0xa9)   // OP_HASH160
            && (txBytes[pos + 2] == 0x14)   // bytes to push
            && (txBytes[pos + 23] == 0x88)  // OP_EQUALVERIFY
            && (txBytes[pos + 24] == 0xac); // OP_CHECKSIG
    }
    // returns true if the bytes located in txBytes by pos and
    // script_len represent a P2SH script
    function isP2SH(bytes txBytes, uint pos, uint script_len) private pure returns (bool) {
        return (script_len == 23)           // 20 byte scripthash + 3 bytes of script
            && (txBytes[pos + 0] == 0xa9)   // OP_HASH160
            && (txBytes[pos + 1] == 0x14)   // bytes to push
            && (txBytes[pos + 22] == 0x87); // OP_EQUAL
    }
    // Get the pubkeyhash / scripthash from an output script. Assumes
    // pay-to-pubkey-hash (P2PKH) or pay-to-script-hash (P2SH) outputs.
    // Returns the pubkeyhash/ scripthash, or zero if unknown output.
    function parseOutputScript(bytes txBytes, uint pos, uint script_len) private pure
             returns (bytes20)
    {
        if (isP2PKH(txBytes, pos, script_len)) {
            return sliceBytes20(txBytes, pos + 3);
        } else if (isP2SH(txBytes, pos, script_len)) {
            return sliceBytes20(txBytes, pos + 2);
        } else {
            return;
        }
    }

    // Get the pubkeyhash from an output script. Assumes
    // pay-to-pubkey-hash (P2PKH) outputs.
    // Returns the pubkeyhash, or zero if unknown output.
    function parseP2PKHOutputScript(bytes txBytes, uint pos, uint script_len) private pure
             returns (bytes20)
    {
        if (isP2PKH(txBytes, pos, script_len)) {
            return sliceBytes20(txBytes, pos + 3);
        } else {
            return;
        }
    }


    // Parse a P2PKH scriptSig
    function parseScriptSig(bytes txBytes, uint pos) private pure
             returns (bytes, bytes32, bool, uint)
    {
        bytes memory sig;
        bytes32 pubKey;
        bool odd;
        (sig, pos) = parseSignature(txBytes, pos);
        (pubKey, odd, pos) = parsePubKey(txBytes, pos);
        return (sig, pubKey, odd, pos);
    }

    // Extract a signature
    function parseSignature(bytes txBytes, uint pos) private pure
             returns (bytes, uint)
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
    function parsePubKey(bytes txBytes, uint pos) private pure
             returns (bytes32, bool, uint)
    {
        uint8 op;
        (op, pos) = getOpcode(txBytes, pos);
        //FIXME: Add support for uncompressed public keys
        require(op == 33);
        bytes32 pubKey;
        bool odd = txBytes[pos] == 0x03;
        pos += 1;
        assembly {
            pubKey := mload(add(add(txBytes, 0x20), pos))
        }
        pos += 32;
        return (pubKey, odd, pos);
    }

    // Read next opcode from script
    function getOpcode(bytes txBytes, uint pos) private pure
             returns (uint8, uint)
    {
        return (uint8(txBytes[pos]), pos + 1);
    }

    function expmod(uint256 base, uint256 e, uint256 m) internal returns (uint256 o) {
        assembly {
            // pointer to free memory
            let p := mload(0x40)
            mstore(p, 0x20)             // Length of Base
            mstore(add(p, 0x20), 0x20)  // Length of Exponent
            mstore(add(p, 0x40), 0x20)  // Length of Modulus
            mstore(add(p, 0x60), base)  // Base
            mstore(add(p, 0x80), e)     // Exponent
            mstore(add(p, 0xa0), m)     // Modulus
            // call modexp precompile!
            if iszero(call(not(0), 0x05, 0, p, 0xc0, p, 0x20)) {
                revert(0, 0)
            }
            // data
            o := mload(p)
        }
    }

    function pub2address(uint x, bool odd) internal returns (address) {
        // First, uncompress pub key
        uint yy = mulmod(x, x, p);
        yy = mulmod(yy, x, p);
        yy = addmod(yy, 7, p);
        uint y = expmod(yy, q, p);
        if (((y & 1) == 1) != odd) {
          y = p - y;
        }
        require(yy == mulmod(y, y, p));
        // Now, with uncompressed x and y, create the address
        return address(keccak256(abi.encodePacked(x, y)));
    }

    // Gets the public key hash given a public key
    function pub2PubKeyHash(bytes32 pub, bool odd) internal pure returns (bytes20) {
        byte firstByte = odd ? byte(0x03) : byte(0x02);
        return ripemd160(abi.encodePacked(sha256(abi.encodePacked(firstByte, pub))));
    }

    // @dev - convert an unsigned integer from little-endian to big-endian representation
    //
    // @param _input - little-endian value
    // @return - input value in big-endian format
    function flip32Bytes(uint _input) internal pure returns (uint result) {
        assembly {
            let pos := mload(0x40)
            for { let i := 0 } lt(i, 32) { i := add(i, 1) } {
                mstore8(add(pos, i), byte(sub(31, i), _input))
            }
            result := mload(pos)
        }
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

    function parseAuxPoW(bytes rawBytes, uint pos, uint len) internal view
             returns (AuxPoW memory auxpow)
    {
        // we need to traverse the bytes with a pointer because some fields are of variable length
        pos += 80; // skip non-AuxPoW header
        // auxpow.firstBytes = sliceBytes32Int(rawBytes, pos);
        uint slicePos;
        uint inputScriptPos;
        (slicePos, inputScriptPos) = getSlicePosAndScriptPos(rawBytes, pos);
        auxpow.txHash = dblShaFlipMem(rawBytes, pos, slicePos - pos);
        pos = slicePos;
        auxpow.scryptHash = sliceBytes32Int(rawBytes, pos);
        pos += 32;
        (auxpow.parentMerkleProof, pos) = scanMerkleBranch(rawBytes, pos, 0);
        auxpow.coinbaseTxIndex = getBytesLE(rawBytes, pos, 32);
        pos += 4;
        (auxpow.chainMerkleProof, pos) = scanMerkleBranch(rawBytes, pos, 0);
        auxpow.dogeHashIndex = getBytesLE(rawBytes, pos, 32);
        pos += 40; // skip hash that was just read, parent version and prev block
        auxpow.parentMerkleRoot = sliceBytes32Int(rawBytes, pos);
        pos += 40; // skip root that was just read, parent block timestamp and bits
        auxpow.parentNonce = getBytesLE(rawBytes, pos, 32);
        uint coinbaseMerkleRootPosition;
        (auxpow.coinbaseMerkleRoot, coinbaseMerkleRootPosition, auxpow.coinbaseMerkleRootCode) = findCoinbaseMerkleRoot(rawBytes);
        if (coinbaseMerkleRootPosition - inputScriptPos > 20 && auxpow.coinbaseMerkleRootCode == 1) {
            // if it was found once and only once but not in the first 20 bytes, return this error code
            auxpow.coinbaseMerkleRootCode = ERR_NOT_IN_FIRST_20;
        }
    }

    // @dev - looks for {0xfa, 0xbe, 'm', 'm'} byte sequence
    // returns the following 32 bytes if it appears once and only once,
    // 0 otherwise
    // also returns the position where the bytes first appear
    function findCoinbaseMerkleRoot(bytes rawBytes) private pure
             returns (uint, uint, uint)
    {
        uint position;
        bool found = false;

        for (uint i = 0; i < rawBytes.length; ++i) {
            if (rawBytes[i] == 0xfa && rawBytes[i+1] == 0xbe && rawBytes[i+2] == 0x6d && rawBytes[i+3] == 0x6d) {
                if (found) { // found twice
                    return (0, position - 4, ERR_FOUND_TWICE);
                } else {
                    found = true;
                    position = i + 4;
                }
            }
        }

        if (!found) { // no merge mining header
            return (0, position - 4, ERR_NO_MERGE_HEADER);
        } else {
            return (sliceBytes32Int(rawBytes, position), position - 4, 1);
        }
    }

    // @dev - Evaluate the merkle root
    //
    // Given an array of hashes it calculates the
    // root of the merkle tree.
    //
    // @return root of merkle tree
    function makeMerkle(bytes32[] hashes2) external pure returns (bytes32) {
        bytes32[] memory hashes = hashes2;
        uint length = hashes.length;
        if (length == 1) return hashes[0];
        require(length > 0);
        uint i;
        uint j;
        uint k;
        k = 0;
        while (length > 1) {
            k = 0;
            for (i = 0; i < length; i += 2) {
                j = i+1<length ? i+1 : length-1;
                hashes[k] = bytes32(concatHash(uint(hashes[i]), uint(hashes[j])));
                k += 1;
            }
            length = k;
        }
        return hashes[0];
    }

    // @dev - For a valid proof, returns the root of the Merkle tree.
    //
    // @param _txHash - transaction hash
    // @param _txIndex - transaction's index within the block it's assumed to be in
    // @param _siblings - transaction's Merkle siblings
    // @return - Merkle tree root of the block the transaction belongs to if the proof is valid,
    // garbage if it's invalid
    function computeMerkle(uint _txHash, uint _txIndex, uint[] _siblings) internal pure returns (uint) {
        uint resultHash = _txHash;
        uint i = 0;
        while (i < _siblings.length) {
            uint proofHex = _siblings[i];

            uint sideOfSiblings = _txIndex % 2;  // 0 means _siblings is on the right; 1 means left

            uint left;
            uint right;
            if (sideOfSiblings == 1) {
                left = proofHex;
                right = resultHash;
            } else if (sideOfSiblings == 0) {
                left = resultHash;
                right = proofHex;
            }

            resultHash = concatHash(left, right);

            _txIndex /= 2;
            i += 1;
        }

        return resultHash;
    }

    // @dev - calculates the Merkle root of a tree containing Litecoin transactions
    // in order to prove that `ap`'s coinbase tx is in that Litecoin block.
    //
    // @param _ap - AuxPoW information
    // @return - Merkle root of Litecoin block that the Dogecoin block
    // with this info was mined in if AuxPoW Merkle proof is correct,
    // garbage otherwise
    function computeParentMerkle(AuxPoW _ap) internal pure returns (uint) {
        return flip32Bytes(computeMerkle(_ap.txHash,
                                         _ap.coinbaseTxIndex,
                                         _ap.parentMerkleProof));
    }

    // @dev - calculates the Merkle root of a tree containing auxiliary block hashes
    // in order to prove that the Dogecoin block identified by _blockHash
    // was merge-mined in a Litecoin block.
    //
    // @param _blockHash - SHA-256 hash of a certain Dogecoin block
    // @param _ap - AuxPoW information corresponding to said block
    // @return - Merkle root of auxiliary chain tree
    // if AuxPoW Merkle proof is correct, garbage otherwise
    function computeChainMerkle(uint _blockHash, AuxPoW _ap) internal pure returns (uint) {
        return computeMerkle(_blockHash,
                             _ap.dogeHashIndex,
                             _ap.chainMerkleProof);
    }

    // @dev - Helper function for Merkle root calculation.
    // Given two sibling nodes in a Merkle tree, calculate their parent.
    // Concatenates hashes `_tx1` and `_tx2`, then hashes the result.
    //
    // @param _tx1 - Merkle node (either root or internal node)
    // @param _tx2 - Merkle node (either root or internal node), has to be `_tx1`'s sibling
    // @return - `_tx1` and `_tx2`'s parent, i.e. the result of concatenating them,
    // hashing that twice and flipping the bytes.
    function concatHash(uint _tx1, uint _tx2) internal pure returns (uint) {
        return flip32Bytes(uint(sha256(abi.encodePacked(sha256(abi.encodePacked(flip32Bytes(_tx1), flip32Bytes(_tx2)))))));
    }

    // @dev - checks if a merge-mined block's Merkle proofs are correct,
    // i.e. Doge block hash is in coinbase Merkle tree
    // and coinbase transaction is in parent Merkle tree.
    //
    // @param _blockHash - SHA-256 hash of the block whose Merkle proofs are being checked
    // @param _ap - AuxPoW struct corresponding to the block
    // @return 1 if block was merge-mined and coinbase index, chain Merkle root and Merkle proofs are correct,
    // respective error code otherwise
    function checkAuxPoW(uint _blockHash, AuxPoW _ap) internal pure returns (uint) {
        if (_ap.coinbaseTxIndex != 0) {
            return ERR_COINBASE_INDEX;
        }

        if (_ap.coinbaseMerkleRootCode != 1) {
            return _ap.coinbaseMerkleRootCode;
        }

        if (computeChainMerkle(_blockHash, _ap) != _ap.coinbaseMerkleRoot) {
            return ERR_CHAIN_MERKLE;
        }

        if (computeParentMerkle(_ap) != _ap.parentMerkleRoot) {
            return ERR_PARENT_MERKLE;
        }

        return 1;
    }

    function sha256mem(bytes memory _rawBytes, uint offset, uint len) internal view returns (bytes32 result) {
        assembly {
            // Call sha256 precompiled contract (located in address 0x02) to copy data.
            // Assign to ptr the next available memory position (stored in memory position 0x40).
            let ptr := mload(0x40)
            if iszero(staticcall(gas, 0x02, add(add(_rawBytes, 0x20), offset), len, ptr, 0x20)) {
                revert(0, 0)
            }
            result := mload(ptr)
        }
    }

    // @dev - Bitcoin-way of hashing
    // @param _dataBytes - raw data to be hashed
    // @return - result of applying SHA-256 twice to raw data and then flipping the bytes
    function dblShaFlip(bytes _dataBytes) internal pure returns (uint) {
        return flip32Bytes(uint(sha256(abi.encodePacked(sha256(abi.encodePacked(_dataBytes))))));
    }

    // @dev - Bitcoin-way of hashing
    // @param _dataBytes - raw data to be hashed
    // @return - result of applying SHA-256 twice to raw data and then flipping the bytes
    function dblShaFlipMem(bytes memory _rawBytes, uint offset, uint len) internal view returns (uint) {
        return flip32Bytes(uint(sha256(abi.encodePacked(sha256mem(_rawBytes, offset, len)))));
    }

    // @dev – Read a bytes32 from an offset in the byte array
    function readBytes32(bytes data, uint offset) internal pure returns (bytes32) {
        bytes32 result;
        assembly {
            result := mload(add(add(data, 0x20), offset))
        }
        return result;
    }

    // @dev – Read an uint32 from an offset in the byte array
    function readUint32(bytes data, uint offset) internal pure returns (uint32) {
        uint32 result;
        assembly {
            let word := mload(add(add(data, 0x20), offset))
            result := add(byte(3, word),
                add(mul(byte(2, word), 0x100),
                    add(mul(byte(1, word), 0x10000),
                        mul(byte(0, word), 0x1000000))))
        }
        return result;
    }

    // @dev - Bitcoin-way of computing the target from the 'bits' field of a block header
    // based on http://www.righto.com/2014/02/bitcoin-mining-hard-way-algorithms.html//ref3
    //
    // @param _bits - difficulty in bits format
    // @return - difficulty in target format
    function targetFromBits(uint32 _bits) internal pure returns (uint) {
        uint exp = _bits / 0x1000000;  // 2**24
        uint mant = _bits & 0xffffff;
        return mant * 256**(exp - 3);
    }

    uint constant DOGECOIN_DIFFICULTY_ONE = 0xFFFFF * 256**(0x1e - 3);

    // @dev - Calculate dogecoin difficulty from target
    // https://en.bitcoin.it/wiki/Difficulty
    // Min difficulty for bitcoin is 0x1d00ffff
    // Min difficulty for dogecoin is 0x1e0fffff
    function targetToDiff(uint target) internal pure returns (uint) {
        return DOGECOIN_DIFFICULTY_ONE / target;
    }

    // @dev - Parse an array of bytes32
    function parseBytes32Array(bytes data) external pure returns (bytes32[]) {
        require(data.length % 32 == 0);
        uint count = data.length / 32;
        bytes32[] memory hashes = new bytes32[](count);
        for (uint i=0; i<count; ++i) {
            hashes[i] = readBytes32(data, 32*i);
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
    // @param _blockHeader - Dogecoin block header bytes
    // @param pos - where to start reading version from
    // @return - block's version in big endian format
    function getVersion(bytes memory _blockHeader, uint pos) internal pure returns (uint32 version) {
        assembly {
            let word := mload(add(add(_blockHeader, 0x4), pos))
            version := add(byte(24, word),
                add(mul(byte(25, word), 0x100),
                    add(mul(byte(26, word), 0x10000),
                        mul(byte(27, word), 0x1000000))))
        }
    }

    // @dev - extract previous block field from a raw Dogecoin block header
    //
    // @param _blockHeader - Dogecoin block header bytes
    // @param pos - where to start reading hash from
    // @return - hash of block's parent in big endian format
    function getHashPrevBlock(bytes memory _blockHeader, uint pos) internal pure returns (uint) {
        uint hashPrevBlock;
        assembly {
            hashPrevBlock := mload(add(add(_blockHeader, 0x24), pos))
        }
        return flip32Bytes(hashPrevBlock);
    }

    // @dev - extract Merkle root field from a raw Dogecoin block header
    //
    // @param _blockHeader - Dogecoin block header bytes
    // @param pos - where to start reading root from
    // @return - block's Merkle root in big endian format
    function getHeaderMerkleRoot(bytes _blockHeader, uint pos) private pure returns (uint) {
        uint merkle;
        assembly {
            merkle := mload(add(add(_blockHeader, 0x44), pos))
        }
        return flip32Bytes(merkle);
    }

    // @dev - extract bits field from a raw Dogecoin block header
    //
    // @param _blockHeader - Dogecoin block header bytes
    // @param pos - where to start reading bits from
    // @return - block's difficulty in bits format, also big-endian
    function getBits(bytes memory _blockHeader, uint pos) internal pure returns (uint32 bits) {
        assembly {
            let word := mload(add(add(_blockHeader, 0x50), pos))
            bits := add(byte(24, word),
                add(mul(byte(25, word), 0x100),
                    add(mul(byte(26, word), 0x10000),
                        mul(byte(27, word), 0x1000000))))
        }
    }

    // @dev - extract timestamp field from a raw Dogecoin block header
    //
    // @param _blockHeader - Dogecoin block header bytes
    // @param pos - where to start reading bits from
    // @return - block's timestamp in big-endian format
    function getTimestamp(bytes memory _blockHeader, uint pos) internal pure returns (uint32 time) {
        assembly {
            let word := mload(add(add(_blockHeader, 0x4c), pos))
            time := add(byte(24, word),
                add(mul(byte(25, word), 0x100),
                    add(mul(byte(26, word), 0x10000),
                        mul(byte(27, word), 0x1000000))))
        }
    }

    // @dev - converts raw bytes representation of a Dogecoin block header to struct representation
    //
    // @param _rawBytes - first 80 bytes of a block header
    // @return - exact same header information in BlockHeader struct form
    function parseHeaderBytes(bytes _rawBytes, uint pos) internal view returns (BlockHeader bh) {
        bh.version = getVersion(_rawBytes, pos);
        bh.time = getTimestamp(_rawBytes, pos);
        bh.bits = getBits(_rawBytes, pos);
        bh.blockHash = dblShaFlipMem(_rawBytes, pos, 80);
        bh.prevBlock = getHashPrevBlock(_rawBytes, pos);
        bh.merkleRoot = getHeaderMerkleRoot(_rawBytes, pos);
    }

    uint32 constant VERSION_AUXPOW = (1 << 8);

    // @dev - Converts a bytes of size 4 to uint32,
    // e.g. for input [0x01, 0x02, 0x03 0x04] returns 0x01020304
    function bytesToUint32Flipped(bytes input, uint pos) internal pure returns (uint32 result) {
        result = uint32(input[pos]) + uint32(input[pos + 1])*(2**8) + uint32(input[pos + 2])*(2**16) + uint32(input[pos + 3])*(2**24);
    }

    // @dev - checks version to determine if a block has merge mining information
    function isMergeMined(bytes _rawBytes, uint pos) internal pure returns (bool) {
        return bytesToUint32Flipped(_rawBytes, pos) & VERSION_AUXPOW != 0;
    }

    // @dev - checks version to determine if a block has merge mining information
    function isMergeMined(BlockHeader _blockHeader) internal pure returns (bool) {
        return _blockHeader.version & VERSION_AUXPOW != 0;
    }

    // @dev - Verify block header
    // @return - true when a the block header is valid
    function verifyBlockHeader(bytes _blockHeaderBytes, uint pos, uint len, uint _scryptBlockHash) external view returns (uint, uint, uint) {
        BlockHeader memory blockHeader = parseHeaderBytes(_blockHeaderBytes, pos);
        uint blockSha256Hash = blockHeader.blockHash;
        if (isMergeMined(blockHeader)) {
            AuxPoW memory ap = parseAuxPoW(_blockHeaderBytes, pos, len);
            if (flip32Bytes(ap.scryptHash) > targetFromBits(blockHeader.bits)) {
                return (ERR_PROOF_OF_WORK, blockHeader.blockHash, ap.scryptHash);
            }
            uint auxPoWCode = checkAuxPoW(blockSha256Hash, ap);
            if (auxPoWCode != 1) {
                return (auxPoWCode, blockHeader.blockHash, ap.scryptHash);
            }
            return (0, blockHeader.blockHash, ap.scryptHash);
        } else {
            if (flip32Bytes(_scryptBlockHash) > targetFromBits(blockHeader.bits)) {
                return (ERR_PROOF_OF_WORK, blockHeader.blockHash, _scryptBlockHash);
            }
            return (0, blockHeader.blockHash, _scryptBlockHash);
        }
    }
}

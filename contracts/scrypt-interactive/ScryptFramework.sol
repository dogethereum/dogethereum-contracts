pragma solidity 0.5.16;

/**
* @title ScryptFramework
* @author Christian Reitwiessner
*/
contract ScryptFramework {
    // The state object, can be used in both generating and verifying mode.
    // In generating mode, only vars and fullMemory is used, in verifying
    // mode only vars and memoryHash is used.
    struct State {
        uint[4] vars;
        bytes32 memoryHash;
        // We need the input as part of the state because it is required
        // for the final step.
        bytes32 inputHash;
        // This is not available in verification mode.
        uint[] fullMemory;
    }
    // This is the witness data that is generated in generating mode
    // and used for verification in verification mode.
    struct Proofs {
        bool generateProofs;
        bool verificationError;
        bytes32[] proof;
    }

    // Only used for testing.
    /**
    * @dev hashes a state struct instance
    *
    * @param state the state struct instance to hash
    *
    * @return returns the hash
    */
    function hashState(State memory state) pure internal returns (bytes32) {
        return keccak256(abi.encodePacked(state.memoryHash, state.vars, state.inputHash));
    }

    /**
    * @dev serializes a State struct instance
    *
    * @param state the State struct instance to be serialized
    *
    * @return returns the serialized Struct instance
    */
    function encodeState(State memory state) pure internal returns (bytes memory r) {
        r = new bytes(0x20 * 4 + 0x20 + 0x20);
        uint[4] memory vars = state.vars;
        bytes32 memoryHash = state.memoryHash;
        bytes32 inputHash = state.inputHash;
        assembly {
            mstore(add(r, 0x20), mload(add(vars, 0x00)))
            mstore(add(r, 0x40), mload(add(vars, 0x20)))
            mstore(add(r, 0x60), mload(add(vars, 0x40)))
            mstore(add(r, 0x80), mload(add(vars, 0x60)))
            mstore(add(r, 0xa0), memoryHash)
            mstore(add(r, 0xc0), inputHash)
        }
    }

    /**
    * @dev de-serializes a State struct instance
    *
    * @param encoded the serialized State struct instance
    *
    * @return returns false if the input size is wrong and a State struct instance
    */
    function decodeState(bytes memory encoded) pure internal returns (bool error, State memory state) {
        if (encoded.length != 0x20 * 4 + 0x20 + 0x20) {
            return (true, state);
        }
        uint[4] memory vars = state.vars;
        bytes32 memoryHash;
        bytes32 inputHash;
        assembly {
            mstore(add(vars, 0x00), mload(add(encoded, 0x20)))
            mstore(add(vars, 0x20), mload(add(encoded, 0x40)))
            mstore(add(vars, 0x40), mload(add(encoded, 0x60)))
            mstore(add(vars, 0x60), mload(add(encoded, 0x80)))
            memoryHash := mload(add(encoded, 0xa0))
            inputHash := mload(add(encoded, 0xc0))
        }
        state.memoryHash = memoryHash;
        state.inputHash = inputHash;
        return (false, state);
    }

    /**
    * @dev checks for equality of a and b's hash
    *
    * @param a the first equality operand
    * @param b the second equality operand
    *
    * @return return true or false
    */
    function equal(bytes memory a, bytes memory b) pure internal returns (bool) {
      return keccak256(a) == keccak256(b);
    }

    /**
    * @dev populates a State struct instance
    *
    * @param input the input that is going to be put inside the State struct instance
    *
    * @return  returns a State struct instance
    */
    function inputToState(bytes memory input) pure internal returns (State memory state)
    {
        state.inputHash = keccak256(input);
        state.vars = KeyDeriv.pbkdf2(input, input, 128);
        state.vars[0] = Salsa8.endianConvert256bit(state.vars[0]);
        state.vars[1] = Salsa8.endianConvert256bit(state.vars[1]);
        state.vars[2] = Salsa8.endianConvert256bit(state.vars[2]);
        state.vars[3] = Salsa8.endianConvert256bit(state.vars[3]);
        // This is the root hash of empty memory.
        state.memoryHash = bytes32(0xe82cea94884b1b895ea0742840a3b19249a723810fd1b04d8564d675b0a416f1);
        initMemory(state);
    }

    /**
    * @dev change the state to the output format
    *
    * @param state the final state
    *
    * @return the output
    */
    function finalStateToOutput(State memory state, bytes memory input) pure internal returns (bytes memory output)
    {
        require(keccak256(input) == state.inputHash);
        state.vars[0] = Salsa8.endianConvert256bit(state.vars[0]);
        state.vars[1] = Salsa8.endianConvert256bit(state.vars[1]);
        state.vars[2] = Salsa8.endianConvert256bit(state.vars[2]);
        state.vars[3] = Salsa8.endianConvert256bit(state.vars[3]);
        bytes memory val = uint4ToBytes(state.vars);
        uint[4] memory values = KeyDeriv.pbkdf2(input, val, 32);
        require(values[1] == 0 && values[2] == 0 && values[3] == 0);
        output = new bytes(32);
        uint val0 = values[0];
        assembly { mstore(add(output, 0x20), val0) }
    }

    /**
    * @dev casts a bytes32 array to a bytes array
    *
    * @param b the input
    *
    * @return returns the bytes array
    */
    function toBytes(bytes32[] memory b) pure internal returns (bytes memory r)
    {
        uint len = b.length * 0x20;
        r = new bytes(len);
        assembly {
          let d := add(r, 0x20)
          let s := add(b, 0x20)
          for { let i := 0 } lt(i, len) { i := add(i, 0x20) } {
            mstore(add(d, i), mload(add(s, i)))
          }
        }
    }

    /**
    * @dev casts a bytes array into a bytes32 array
    *
    * @param b the input bytes array
    *
    * @return returns whether the input length module 0x20 is 0 and the bytes32 array
    */
    function toArray(bytes memory b) pure internal returns (bool error, bytes32[] memory r)
    {
        if (b.length % 0x20 != 0) {
            return (true, r);
        }
        uint len = b.length;
        r = new bytes32[](b.length / 0x20);
        assembly {
            let d := add(r, 0x20)
            let s := add(b, 0x20)
            for { let i := 0 } lt(i, len) { i := add(i, 0x20) } {
                mstore(add(d, i), mload(add(s, i)))
            }
        }
    }

    /**
    * @dev convert a 4-member array into a byte stream
    *
    * @param val the input array that has 4 members
    *
    * @return the byte stream
    */
    function uint4ToBytes(uint[4] memory val) pure internal returns (bytes memory r)
    {
        r = new bytes(4 * 32);
        uint v = val[0];
        assembly { mstore(add(r, 0x20), v) }
        v = val[1];
        assembly { mstore(add(r, 0x40), v) }
        v = val[2];
        assembly { mstore(add(r, 0x60), v) }
        v = val[3];
        assembly { mstore(add(r, 0x80), v) }
    }

    // Virtual functions to be implemented in either the runner/prover or the verifier.
    function initMemory(State memory state) pure internal;
    function writeMemory(State memory state, uint index, uint[4] memory values, Proofs memory proofs) pure internal;
    function readMemory(State memory state, uint index, Proofs memory proofs) pure internal returns (uint, uint, uint, uint);

    /**
    * @dev runs a single step, modifying the state.
    *      This in turn calls the virtual functions readMemory and writeMemory.
    *
    * @param state the state structure
    * @param step which step to run
    * @param proofs the proofs structure
    *
    * @return none
    */
    function runStep(State memory state, uint step, Proofs memory proofs) pure internal {
        require(step < 2048);
        if (step < 1024) {
            writeMemory(state, step, state.vars, proofs);
            state.vars = Salsa8.round(state.vars);
        } else {
            uint readIndex = (state.vars[2] / 0x100000000000000000000000000000000000000000000000000000000) % 1024;
            (uint va, uint vb, uint vc, uint vd) = readMemory(state, readIndex, proofs);
            state.vars = Salsa8.round([
                state.vars[0] ^ va,
                state.vars[1] ^ vb,
                state.vars[2] ^ vc,
                state.vars[3] ^ vd
            ]);
        }
    }
}

library Salsa8 {
    uint constant m0 = 0x100000000000000000000000000000000000000000000000000000000;
    uint constant m1 = 0x1000000000000000000000000000000000000000000000000;
    uint constant m2 = 0x010000000000000000000000000000000000000000;
    uint constant m3 = 0x100000000000000000000000000000000;
    uint constant m4 = 0x1000000000000000000000000;
    uint constant m5 = 0x10000000000000000;
    uint constant m6 = 0x100000000;
    uint constant m7 = 0x1;

    /**
    * @dev calculates a quarter of a slasa round on a row/column of the matrix
    *
    * @param y0 the first element
    * @param y1 the second element
    * @param y2 the third element
    * @param y3 the fourth element
    *
    * @return the updated elements after a quarter of a salsa round on a row/column of the matrix
    */
    function quarter(uint32 y0, uint32 y1, uint32 y2, uint32 y3)
        pure internal returns (uint32, uint32, uint32, uint32)
    {
        uint32 t;
        t = y0 + y3;
        y1 = y1 ^ ((t * 2**7) | (t / 2**(32-7)));
        t = y1 + y0;
        y2 = y2 ^ ((t * 2**9) | (t / 2**(32-9)));
        t = y2 + y1;
        y3 = y3 ^ ((t * 2**13) | (t / 2**(32-13)));
        t = y3 + y2;
        y0 = y0 ^ ((t * 2**18) | (t / 2**(32-18)));
        return (y0, y1, y2, y3);
    }

    /**
    * @dev extracts a 32-bit word from the uint256 word.
    *
    * @param data the uint256 word from where we would like to extract a 32-bit word.
    * @param word which 32-bit word to extract, 0 denotes the most signifacant 32-bit word.
    *
    * @return return the 32-bit extracted word
    */
    function get(uint data, uint word) pure internal returns (uint32 x)
    {
        return uint32(data / 2**(256 - word * 32 - 32));
    }

    /**
    * @dev shifts a 32-bit value inside a uint256 for a set amount of 32-bit words to the left
    *
    * @param x the 32-bit value to shift.
    * @param word how many 32-bit words to shift x to the lefy by.
    *
    * @return returns a uint256 value containing x shifted to the left by word*32.
    */
    function put(uint x, uint word) pure internal returns (uint) {
        return x * 2**(256 - word * 32 - 32);
    }

    /**
    * @dev calculates a slasa transposed rounds by doing the round on the rows.
    *
    * @param first a uint256 value containing the first half of the salsa matrix i.e. the first 8 elements.
    * @param second a uint256  value containing the second half of the salsa matrix i.e. the second 8 elements.
    *
    * @return returns the updated first and second half of the salsa matrix.
    */
    function rowround(uint first, uint second) pure internal returns (uint f, uint s)
    {
        (uint32 a, uint32 b, uint32 c, uint32 d) = quarter(uint32(first / m0), uint32(first / m1), uint32(first / m2), uint32(first / m3));
        f = (((((uint(a) * 2**32) | uint(b)) * 2 ** 32) | uint(c)) * 2**32) | uint(d);
        (b,c,d,a) = quarter(uint32(first / m5), uint32(first / m6), uint32(first / m7), uint32(first / m4));
        f = (((((((f * 2**32) | uint(a)) * 2**32) | uint(b)) * 2 ** 32) | uint(c)) * 2**32) | uint(d);
        (c,d,a,b) = quarter(uint32(second / m2), uint32(second / m3), uint32(second / m0), uint32(second / m1));
        s = (((((uint(a) * 2**32) | uint(b)) * 2 ** 32) | uint(c)) * 2**32) | uint(d);
        (d,a,b,c) = quarter(uint32(second / m7), uint32(second / m4), uint32(second / m5), uint32(second / m6));
        s = (((((((s * 2**32) | uint(a)) * 2**32) | uint(b)) * 2 ** 32) | uint(c)) * 2**32) | uint(d);
    }

    /**
    * @dev calculates a salsa column round.
    *
    * @param first a uint256 value containing the first half of the salsa matrix.
    * @param second a uint256 value containing the second half of the salsa matrix.
    *
    * @return f, s
    */
    function columnround(uint first, uint second) pure internal returns (uint f, uint s)
    {
        (uint32 a, uint32 b, uint32 c, uint32 d) = quarter(uint32(first / m0), uint32(first / m4), uint32(second / m0), uint32(second / m4));
        f = (uint(a) * m0) | (uint(b) * m4);
        s = (uint(c) * m0) | (uint(d) * m4);
        (a,b,c,d) = quarter(uint32(first / m5), uint32(second / m1), uint32(second / m5), uint32(first / m1));
        f |= (uint(a) * m5) | (uint(d) * m1);
        s |= (uint(b) * m1) | (uint(c) * m5);
        (a,b,c,d) = quarter(uint32(second / m2), uint32(second / m6), uint32(first / m2), uint32(first / m6));
        f |= (uint(c) * m2) | (uint(d) * m6);
        s |= (uint(a) * m2) | (uint(b) * m6);
        (a,b,c,d) = quarter(uint32(second / m7), uint32(first / m3), uint32(first / m7), uint32(second / m3));
        f |= (uint(b) * m3) | (uint(c) * m7);
        s |= (uint(a) * m7) | (uint(d) * m3);
    }

    /**
    * @dev run salsa20_8 on the input matrix
    *
    * @param _first the first half of the input matrix to salsa.
    * @param _second the sesond half of the input matrix to salsa.
    *
    * @return returns the result matrix in the form of two uint256 values.
    */
    function salsa20_8(uint _first, uint _second) pure internal returns (uint rfirst, uint rsecond) {
        uint first = _first;
        uint second = _second;
        for (uint i = 0; i < 8; i += 2)
        {
            (first, second) = columnround(first, second);
            (first, second) = rowround(first, second);
        }
        for (uint i = 0; i < 8; i++)
        {
            rfirst |= put(get(_first, i) + get(first, i), i);
            rsecond |= put(get(_second, i) + get(second, i), i);
        }
    }

    /**
    * @dev flips the endianness of a 256-bit value
    *
    * @param x the input
    *
    * @return the flipped value
    */
    function endianConvert256bit(uint x) pure internal returns (uint) {
        return
            endianConvert32bit(x / m0) * m0 +
            endianConvert32bit(x / m1) * m1 +
            endianConvert32bit(x / m2) * m2 +
            endianConvert32bit(x / m3) * m3 +
            endianConvert32bit(x / m4) * m4 +
            endianConvert32bit(x / m5) * m5 +
            endianConvert32bit(x / m6) * m6 +
            endianConvert32bit(x / m7) * m7;
    }

    /**
    * @dev flips endianness for a 32-bit input
    *
    * @param x the 32-bit value to have its endianness flipped
    *
    * @return the flipped value
    */
    function endianConvert32bit(uint x) pure internal returns (uint) {
        return
            (x & 0xff) * 0x1000000 +
            (x & 0xff00) * 0x100 +
            (x & 0xff0000) / 0x100 +
            (x & 0xff000000) / 0x1000000;
    }

    /**
    * @dev runs Salsa8 on input values
    *
    * @param values the input values for Salsa8
    *
    * @return returns the result of running Salsa8 on the input values
    */
    function round(uint[4] memory values) pure internal returns (uint[4] memory) {
        (uint a, uint b, uint c, uint d) = (values[0], values[1], values[2], values[3]);
        (a, b) = salsa20_8(a ^ c, b ^ d);
        (c, d) = salsa20_8(a ^ c, b ^ d);
        return [a, b, c, d];
    }
}

library KeyDeriv {
  /**
  * @dev hmacsha256
  *
  * @param key the key
  * @param message the message to hash
  *
  * @return the hash result
  */
    function hmacsha256(bytes memory key, bytes memory message) pure internal returns (bytes32) {
        bytes32 keyl;
        bytes32 keyr;
        uint i;
        if (key.length > 64) {
            keyl = sha256(key);
        } else {
            for (i = 0; i < key.length && i < 32; i++)
                keyl |= bytes32(uint(uint8(key[i])) * 2**(8 * (31 - i)));
            for (i = 32; i < key.length && i < 64; i++)
                keyr |= bytes32(uint(uint8(key[i])) * 2**(8 * (63 - i)));
        }
        bytes32 threesix = 0x3636363636363636363636363636363636363636363636363636363636363636;
        bytes32 fivec = 0x5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c;
        return sha256(abi.encodePacked(fivec ^ keyl, fivec ^ keyr, sha256(abi.encodePacked(threesix ^ keyl, threesix ^ keyr, message))));
    }

    /// PBKDF2 restricted to c=1, hash = hmacsha256 and dklen being a multiple of 32 not larger than 128
    /**
    * @dev pbkdf2
    *
    * @param key the password
    * @param salt cryptographic salt
    * @param dklen desired length of the key
    *
    * @return returns the generated key
    */
    function pbkdf2(bytes memory key, bytes memory salt, uint dklen) pure internal returns (uint[4] memory r) {
        bytes memory message = new bytes(salt.length + 4);
        for (uint i = 0; i < salt.length; i++)
            message[i] = salt[i];
        for (uint i = 0; i * 32 < dklen; i++) {
            message[message.length - 1] = bytes1(uint8(i + 1));
            r[i] = uint(hmacsha256(key, message));
        }
    }
}

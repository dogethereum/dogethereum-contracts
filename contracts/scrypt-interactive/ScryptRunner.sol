// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import {ScryptFramework} from "./ScryptFramework.sol";

/**
 * @title ScryptRunner
 * @author Christian Reitwiessner
 */
contract ScryptRunner is ScryptFramework {
    /**
     * @dev reserve 4096 bytes for the fullMemory member of the State struct
     *
     * @param state the State struct instance
     */
    function initMemory(State memory state) internal pure override {
        state.fullMemory = new uint256[](4 * 1024);
    }

    /**
     * @dev run scrypt up to a certain step - just used for testing
     *
     * @param input the input
     * @param upToStep which step to stop running at
     *
     * @return stateHash The state hash
     * @return vars The state variables
     * @return memoryHash The memoryHash
     * @return proof The merkle proof
     * @return output The output byte array
     */
    function run(bytes memory input, uint256 upToStep)
        public
        pure
        returns (
            bytes32 stateHash,
            uint256[4] memory vars,
            bytes32 memoryHash,
            bytes32[] memory proof,
            bytes memory output
        )
    {
        State memory s = inputToState(input);
        Proofs memory proofs;
        if (upToStep > 0) {
            uint256 internalStep = upToStep - 1;
            for (uint256 i = 0; i < internalStep; i++) {
                runStep(s, i, proofs);
            }
            proofs.generateProofs = true;
            if (internalStep < 2048) {
                runStep(s, internalStep, proofs);
            } else {
                require(s.inputHash == keccak256(input));
                output = finalStateToOutput(s, input);
            }
        }
        return (hashState(s), s.vars, s.memoryHash, proofs.proof, output);
    }

    /**
     * @dev run scrypt up to a certain step and return the state and proof,
     *      The proof being the one required to get from the previous step to the given one.
     */
    function getStateAndProof(bytes memory input, uint256 step)
        public
        pure
        returns (bytes memory state, bytes memory proof)
    {
        require(step <= 2050, "Step can't be higher than 2050");
        if (step == 0) {
            return (input, proof);
        }
        State memory s = inputToState(input);
        Proofs memory proofs;
        if (step == 1) {
            return (encodeState(s), proof);
        }
        {
            uint256 maxStep = step <= 2049 ? step : 2049;
            uint256 i = 2;
            for (; i < maxStep; i++) {
                runStep(s, i - 2, proofs);
            }
            proofs.generateProofs = true;
            runStep(s, i - 2, proofs);
        }
        if (step < 2050) {
            return (encodeState(s), toBytes(proofs.proof));
        }
        return (finalStateToOutput(s, input), input);
    }

    function getStateProofAndHash(bytes memory input, uint256 step)
        public
        pure
        returns (
            bytes memory state,
            bytes memory proof,
            bytes32 stateHash
        )
    {
        (state, proof) = getStateAndProof(input, step);
        return (state, proof, keccak256(state));
    }

    /**
     * @dev get the state hash of a specific step.
     */
    function getStateHash(bytes memory input, uint256 step)
        public
        pure
        returns (bytes32 stateHash)
    {
        require(step <= 2050);

        (bytes memory state, ) = getStateAndProof(input, step);
        return keccak256(state);
    }

    // The proof for reading memory consists of the values read from memory
    // plus a list of hashes from leaf to root.
    /**
     * @dev read memory and update proofs
     *
     * @param state the State struct instance
     * @param index the index at which to read from fullMemory
     * @param proofs the merkle proofs for the read
     *
     * @return a The first word from fullMem
     * @return b The second word from fullMem
     * @return c The third word from fullMem
     * @return d The fourth word from fullMem
     */
    function readMemory(
        State memory state,
        uint256 index,
        Proofs memory proofs
    )
        internal
        pure
        override
        returns (
            uint256 a,
            uint256 b,
            uint256 c,
            uint256 d
        )
    {
        require(index < 1024);
        uint256 pos = 0x20 * 4 * index;
        uint256[] memory fullMem = state.fullMemory;
        assembly {
            pos := add(pos, 0x20)
            a := mload(add(fullMem, pos))
            pos := add(pos, 0x20)
            b := mload(add(fullMem, pos))
            pos := add(pos, 0x20)
            c := mload(add(fullMem, pos))
            pos := add(pos, 0x20)
            d := mload(add(fullMem, pos))
        }
        if (proofs.generateProofs) {
            (proofs.proof, state.memoryHash) = generateMemoryProof(
                state.fullMemory,
                index
            );
            proofs.proof[0] = bytes32(a);
            proofs.proof[1] = bytes32(b);
            proofs.proof[2] = bytes32(c);
            proofs.proof[3] = bytes32(d);
        }
    }

    // The proof for writing to memory consists of the four old values in
    // memory followed by a list of hashes from leaf to root.
    /**
     * @dev write to memory
     *
     * @param state the State struct
     * @param index the index at which the write is perfomed
     * @param values the values that are going to be written in fullMemory
     * @param proofs the proofs to be updated
     */
    function writeMemory(
        State memory state,
        uint256 index,
        uint256[4] memory values,
        Proofs memory proofs
    ) internal pure override {
        require(index < 1024);
        uint256 pos = 0x20 * 4 * index;
        uint256[] memory fullMem = state.fullMemory;
        uint256[4] memory oldValues;
        if (proofs.generateProofs) {
            oldValues[0] = fullMem[4 * index + 0];
            oldValues[1] = fullMem[4 * index + 1];
            oldValues[2] = fullMem[4 * index + 2];
            oldValues[3] = fullMem[4 * index + 3];
        }
        (uint256 a, uint256 b, uint256 c, uint256 d) = (
            values[0],
            values[1],
            values[2],
            values[3]
        );
        assembly {
            pos := add(pos, 0x20)
            mstore(add(fullMem, pos), a)
            pos := add(pos, 0x20)
            mstore(add(fullMem, pos), b)
            pos := add(pos, 0x20)
            mstore(add(fullMem, pos), c)
            pos := add(pos, 0x20)
            mstore(add(fullMem, pos), d)
        }
        if (proofs.generateProofs) {
            (proofs.proof, state.memoryHash) = generateMemoryProof(
                state.fullMemory,
                index
            );
            // We need the values before we write - the siblings will still be the same.
            proofs.proof[0] = bytes32(oldValues[0]);
            proofs.proof[1] = bytes32(oldValues[1]);
            proofs.proof[2] = bytes32(oldValues[2]);
            proofs.proof[3] = bytes32(oldValues[3]);
        }
    }

    // Generate a proof that shows that the memory root hash was updated correctly.
    // Returns the value stored at the index (4 array elemets) followed by
    // a list of siblings (from leaf to root) and the new root hash.
    // This assumes that index is multiplied by four.
    // Since we know that memory is only written in sequence, this might be
    // optimized, but we keep it general for now.
    /**
     * @dev generate proof that shows the memory root has been updated correctly
     *
     * @param fullMem full memory
     * @param index the index of the value to be retunred
     *
     * @return proof The merkle proof
     * @return value The value stored at index
     */
    function generateMemoryProof(uint256[] memory fullMem, uint256 index)
        internal
        pure
        returns (bytes32[] memory proof, bytes32 value)
    {
        uint256 access = index;
        proof = new bytes32[](14);
        // the first four values will later be changed to either the old value
        // (for writes) or the read value (for reads)
        bytes32[] memory hashes = new bytes32[](1024);
        for (uint256 i = 0; i < 1024; i++) {
            hashes[i] = keccak256(
                abi.encodePacked(
                    fullMem[4 * i + 0],
                    fullMem[4 * i + 1],
                    fullMem[4 * i + 2],
                    fullMem[4 * i + 3]
                )
            );
        }
        uint256 numHashes = 1024;
        for (uint256 step = 4; step < proof.length; step++) {
            proof[step] = hashes[access ^ 1];
            access /= 2;
            numHashes /= 2;
            for (uint256 i = 0; i < numHashes; i++) {
                hashes[i] = keccak256(
                    abi.encodePacked(hashes[2 * i], hashes[2 * i + 1])
                );
            }
        }
        assert(numHashes == 1);
        return (proof, hashes[0]);
    }
}

pragma solidity 0.5.16;

import {ScryptFramework} from "./ScryptFramework.sol";
import {Verifier} from "./Verifier.sol";

/**
* @title ScryptVerifier
* @author Christian Reitwiessner
*/
contract ScryptVerifier is ScryptFramework, Verifier {

    modifier onlyBy(address _account) {
        require(msg.sender == _account);
        _;
    }

    function isInitiallyValid(VerificationSession storage session)
        internal
        returns (bool)
    {
        return session.output.length == 32 && session.highStep == 2049;
    }

    function performStepVerificationSpecific(
        VerificationSession storage,
        uint step,
        bytes memory preState,
        bytes memory postState,
        bytes memory proof
    )
        internal
        returns (bool)
    {
        return verifyStep(step, preState, postState, proof);
    }

    /**
    * @dev verifies a step
    *
    * @param step the index of the step to verify
    * @param preState the previous state's serialized State struct instance
    * @param postState the next step's state's serialized State struct instance
    * @param proof the merkle proof
    *
    * @return returns true on success
    */
    function verifyStep(uint step, bytes memory preState, bytes memory postState, bytes memory proof)
        pure
        public
        returns (bool success)
    {
        State memory state;
        if (step == 0) {
            // pre-state is input
            state = inputToState(preState);
            return equal(encodeState(state), postState);
        }
        bool error;
        (error, state) = decodeState(preState);

        if (error) { return false; }

        if (step < 2049) {
            Proofs memory proofs;
            (error, proofs.proof) = toArray(proof);
            if (error) { return false; }

            runStep(state, step - 1, proofs);
            if (proofs.verificationError) { return false; }

            return equal(encodeState(state), postState);
        } else if (step == 2049) {
            if (keccak256(proof) != state.inputHash) { return false; }
            return equal(finalStateToOutput(state, proof), postState);
        } else {
            return false;
        }
    }

    function initMemory(State memory)
        pure
        internal
    {
    }

    /**
    * @dev extracts the read result from the proof and verifies the proof against the memory root hash
    *
    * @param state the State struct instance
    * @param index the offset
    * @param proofs the proofs
    *
    * @return returns the read result
    */
    function readMemory(State memory state, uint index, Proofs memory proofs)
        pure
        internal
        returns (uint a, uint b, uint c, uint d)
    {
        require(index < 1024);

        preCheckProof(state, index, proofs);

        // Extract read result from proof
        a = uint(proofs.proof[0]);
        b = uint(proofs.proof[1]);
        c = uint(proofs.proof[2]);
        d = uint(proofs.proof[3]);
    }

    /**
    * @dev extract the write result from the proof and verify the proof against the memory root hash
    *
    * @param state the state struct
    * @param index the index of fullMemory at which to write
    * @param values the values to write
    * @param proofs the write proofs
    *
    */
    function writeMemory(State memory state, uint index, uint[4] memory values, Proofs memory proofs)
        pure
        internal
    {
        preCheckProof(state, index, proofs);

        proofs.proof[0] = bytes32(values[0]);
        proofs.proof[1] = bytes32(values[1]);
        proofs.proof[2] = bytes32(values[2]);
        proofs.proof[3] = bytes32(values[3]);

        // Compute the post-hash.
        state.memoryHash = executeProof(proofs.proof, index);
    }

    /**
    * @dev preCheckProof
    *
    * @param state the state vars
    * @param index the index of fullMemory
    * @param proofs the merkle proofs
    *
    * @return return whether the verification passed.
    */
    function preCheckProof(State memory state, uint index, Proofs memory proofs)
        pure
        internal
        returns (bool)
    {
        require(index < 1024);

        if (proofs.proof.length != 14) {
            proofs.verificationError = true;
            return false;
        }
        // Check the pre-hash.
        if (executeProof(proofs.proof, index) != state.memoryHash) {
            proofs.verificationError = true;
            return false;
        }

        return true;
    }

    /**
    * @dev executeProof
    *
    * @param proof something
    * @param index something
    *
    * @return proofHash bytes32
    */
    function executeProof(bytes32[] memory proof, uint index)
        pure
        internal
        returns (bytes32)
    {
        bytes32 h = keccak256(abi.encodePacked(proof[0], proof[1], proof[2], proof[3]));
        for (uint step = 0; step < 10; step++) {
            if (index % 2 == 0) {
                h = keccak256(abi.encodePacked(h, proof[4 + step]));
            } else {
                h = keccak256(abi.encodePacked(proof[4 + step], h));
            }
            index /= 2;
        }
        return h;
    }
}

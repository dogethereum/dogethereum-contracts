// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import {ScryptFramework} from "./ScryptFramework.sol";
import {Verifier} from "./Verifier.sol";

/**
 * @title ScryptVerifier
 * @author Christian Reitwiessner
 */
contract ScryptVerifier is ScryptFramework, Verifier {
    function isInitiallyValid(VerificationSession storage session)
        internal
        view
        override
        returns (bool)
    {
        // TODO: verify that the sender is the ScryptClaims contract.
        return session.output.length == 32 && session.highStep == 2050;
    }

    function performStepVerificationSpecific(
        VerificationSession storage,
        uint256 step,
        bytes memory preState,
        bytes memory postState,
        bytes memory proof
    ) internal pure override returns (bool) {
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
     * @return success True on success
     */
    function verifyStep(
        uint256 step,
        bytes memory preState,
        bytes memory postState,
        bytes memory proof
    ) public pure returns (bool success) {
        State memory state;
        if (step == 0) {
            // pre-state is input
            state = inputToState(preState);
            return equal(encodeState(state), postState);
        }
        bool error;
        (error, state) = decodeState(preState);

        if (error) {
            return false;
        }

        if (step < 2049) {
            Proofs memory proofs;
            (error, proofs.proof) = toArray(proof);
            if (error) {
                return false;
            }

            runStep(state, step - 1, proofs);
            if (proofs.verificationError) {
                return false;
            }

            return equal(encodeState(state), postState);
        } else if (step == 2049) {
            if (keccak256(proof) != state.inputHash) {
                return false;
            }
            return equal(finalStateToOutput(state, proof), postState);
        } else {
            return false;
        }
    }

    function initMemory(State memory) internal pure override {}

    /**
     * @dev extracts the read result from the proof and verifies the proof against the memory root hash
     *
     * @param state the State struct instance
     * @param index the offset
     * @param proofs the proofs
     *
     * @return a First word of the result
     * @return b Second word of the result
     * @return c Third word of the result
     * @return d Fourth word of the result
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
        require(index < 1024, "Memory index over 1024 bytes.");

        preCheckProof(state, index, proofs);

        // Extract read result from proof
        a = uint256(proofs.proof[0]);
        b = uint256(proofs.proof[1]);
        c = uint256(proofs.proof[2]);
        d = uint256(proofs.proof[3]);
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
    function writeMemory(
        State memory state,
        uint256 index,
        uint256[4] memory values,
        Proofs memory proofs
    ) internal pure override {
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
    function preCheckProof(
        State memory state,
        uint256 index,
        Proofs memory proofs
    ) internal pure returns (bool) {
        require(index < 1024, "Memory index over 1024 bytes.");

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
    function executeProof(bytes32[] memory proof, uint256 index)
        internal
        pure
        returns (bytes32)
    {
        bytes32 h = keccak256(
            abi.encodePacked(proof[0], proof[1], proof[2], proof[3])
        );
        for (uint256 step = 0; step < 10; step++) {
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

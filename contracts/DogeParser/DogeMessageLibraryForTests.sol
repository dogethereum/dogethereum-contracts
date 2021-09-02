// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import {DogeMessageLibrary} from './DogeMessageLibrary.sol';

// @dev - Manages a battle session between superblock submitter and challenger
contract DogeMessageLibraryForTests {

    function bytesToUint32Public(bytes memory input) public pure returns (uint32 result) {
        return bytesToUint32(input, 0);
    }

    function bytesToBytes32Public(bytes calldata b) public pure returns (bytes32) {
        return bytesToBytes32(b, 0);
    }

    function sliceArrayPublic(bytes calldata original, uint32 offset, uint32 endIndex) public view returns (bytes memory result) {
        return DogeMessageLibrary.sliceArray(original, offset, endIndex);
    }

    function targetFromBitsPublic(uint32 bits) public pure returns (uint) {
        return DogeMessageLibrary.targetFromBits(bits) ;
    }

    function concatHashPublic(uint tx1, uint tx2) public pure returns (uint) {
        return DogeMessageLibrary.concatHash(tx1, tx2);
    }

    function flip32BytesPublic(uint input) public pure returns (uint) {
        return DogeMessageLibrary.flip32Bytes(input);
    }

    function checkAuxPoWPublic(uint blockHash, bytes calldata auxBytes) public view returns (uint) {
        return checkAuxPoWForTests(blockHash, auxBytes);
    }

    // doesn't check merge mining to see if other error codes work
    function checkAuxPoWForTests(uint blockHash, bytes memory auxBytes) internal view returns (uint) {
        DogeMessageLibrary.AuxPoW memory auxPow = DogeMessageLibrary.parseAuxPoW(auxBytes, 0, auxBytes.length);

        //uint32 version = bytesToUint32Flipped(auxBytes, 0);

        if (!DogeMessageLibrary.isMergeMined(auxBytes, 0)) {
            return ERR_NOT_MERGE_MINED;
        }

        if (auxPow.coinbaseTxIndex != 0) {
            return ERR_COINBASE_INDEX;
        }

        if (auxPow.coinbaseMerkleRootCode != 1) {
            return auxPow.coinbaseMerkleRootCode;
        }

        if (DogeMessageLibrary.computeChainMerkle(blockHash, auxPow) != auxPow.coinbaseMerkleRoot) {
            return ERR_CHAIN_MERKLE;
        }

        if (DogeMessageLibrary.computeParentMerkle(auxPow) != auxPow.parentMerkleRoot) {
            return ERR_PARENT_MERKLE;
        }

        return 1;
    }

    // @dev - Converts a bytes of size 4 to uint32,
    // e.g. for input [0x01, 0x02, 0x03 0x04] returns 0x01020304
    function bytesToUint32(bytes memory input, uint pos) internal pure returns (uint32 result) {
        result = uint32(uint8(input[pos]))*(2**24) + uint32(uint8(input[pos + 1]))*(2**16) + uint32(uint8(input[pos + 2]))*(2**8) + uint32(uint8(input[pos + 3]));
    }

    // @dev converts bytes of any length to bytes32.
    // If `rawBytes` is longer than 32 bytes, it truncates to the 32 leftmost bytes.
    // If it is shorter, it pads with 0s on the left.
    // Should be private, made internal for testing
    //
    // @param rawBytes - arbitrary length bytes
    // @return - leftmost 32 or less bytes of input value; padded if less than 32
    function bytesToBytes32(bytes memory rawBytes, uint pos) internal pure returns (bytes32) {
        bytes32 out;
        assembly {
            out := mload(add(add(rawBytes, 0x20), pos))
        }
        return out;
    }

    function parseLockTransaction(bytes calldata txBytes, bytes20 expected_output_public_key_hash) public pure
             returns (uint, address, uint16) {
        return DogeMessageLibrary.parseLockTransaction(txBytes, expected_output_public_key_hash);
    }

    // Placeholder until parseUnlockTransaction is implemented
    // function parseUnlockTransaction(bytes calldata txBytes, bytes20 expected_output_public_key_hash) public view
    //          returns (uint, address, uint16) {
    //     return DogeMessageLibrary.parseUnlockTransaction(txBytes, expected_output_public_key_hash);
    // }

    //
    // Error / failure codes
    //

    // error codes for storeBlockHeader
    uint constant ERR_DIFFICULTY =  10010;  // difficulty didn't match current difficulty
    uint constant ERR_RETARGET = 10020;  // difficulty didn't match retarget
    uint constant ERR_NO_PREV_BLOCK = 10030;
    uint constant ERR_BLOCK_ALREADY_EXISTS = 10040;
    uint constant ERR_INVALID_HEADER = 10050;
    uint constant ERR_COINBASE_INDEX = 10060; // coinbase tx index within Litecoin merkle isn't 0
    uint constant ERR_NOT_MERGE_MINED = 10070; // trying to check AuxPoW on a block that wasn't merge mined
    uint constant ERR_FOUND_TWICE = 10080; // 0xfabe6d6d found twice
    uint constant ERR_NO_MERGE_HEADER = 10090; // 0xfabe6d6d not found
    uint constant ERR_NOT_IN_FIRST_20 = 10100; // chain Merkle root not within first 20 bytes of coinbase tx
    uint constant ERR_CHAIN_MERKLE = 10110;
    uint constant ERR_PARENT_MERKLE = 10120;
    uint constant ERR_PROOF_OF_WORK = 10130;

    // error codes for verifyTx
    uint constant ERR_BAD_FEE = 20010;
    uint constant ERR_CONFIRMATIONS = 20020;
    uint constant ERR_CHAIN = 20030;
    uint constant ERR_SUPERBLOCK = 20040;
    uint constant ERR_MERKLE_ROOT = 20050;
    uint constant ERR_TX_64BYTE = 20060;

    // error codes for relayTx
    uint constant ERR_RELAY_VERIFY = 30010;
}

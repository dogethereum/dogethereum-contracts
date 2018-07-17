pragma solidity ^0.4.19;

import {DogeTx} from './DogeTx.sol';

// @dev - Manages a battle session between superblock submitter and challenger
contract DogeTxForTests {

    function bytesToUint32Public(bytes memory input) public pure returns (uint32 result) {
        return bytesToUint32(input, 0);
    }

    function bytesToBytes32Public(bytes b) public pure returns (bytes32) {
        return bytesToBytes32(b, 0);
    }

    function sliceArrayPublic(bytes original, uint32 offset, uint32 endIndex) public view returns (bytes result) {
        return DogeTx.sliceArray(original, offset, endIndex);
    }

    //function getBlockHash(uint blockHeight) public view returns (uint) {
    //    return fastGetBlockHash(blockHeight);
    //}


    // return the chainWork of the Tip
    // http://bitcoin.stackexchange.com/questions/26869/what-is-chainwork
    //function getChainWork() public view returns (uint128) {
    //    return getScore(bestBlockHash);
    //}


    // return the difference between the chainWork at
    // the blockchain Tip and its 10th ancestor
    //
    // this is not needed by the relay itself, but is provided in
    // case some contract wants to use the chainWork or Bitcoin network
    // difficulty (which can be derived) as a data feed for some purpose
    //function getAverageChainWork() public view returns (uint) {
    //    uint blockHash = bestBlockHash;

    //    uint128 chainWorkTip = getScore(blockHash);

    //    uint8 i = 0;
    //    while (i < 10) {
    //        blockHash = getPrevBlock(blockHash);
    //        i += 1;
    //    }

        // uint128 chainWork10Ancestors = getScore(blockHash);

    //    return (chainWorkTip - getScore(blockHash));
    //}

    // returns the block header (zeros for a header that does not exist) when
    // sufficient payment is provided.  If payment is insufficient, returns 1-byte of zero.
    //function getBlockHeader(uint blockHash) internal returns (DogeTx.BlockHeader) {
    //    // TODO: incentives
    //    // if (feePaid(blockHash, m_getFeeAmount(blockHash))) {  // in incentive.se
    //    //     GetHeader (blockHash, 0);
    //    //    return(text("\x00"):str);
    //    // }
    //    emit GetHeader(bytes32(blockHash), 1);
    //    return myblocks[blockHash]._blockHeader;
    //}

    //function getPrevBlockPublic(uint blockHash) public view returns (uint) {
    //    return getPrevBlock(blockHash);
    //}

    //function getTimestampPublic(uint blockHash) public view returns (uint32 result) {
    //    return getTimestamp(blockHash);
    //}

    //function getBitsPublic(uint blockHash) public view returns (uint32 result) {
    //    return getBits(blockHash);
    //}

    function targetFromBitsPublic(uint32 bits) public pure returns (uint) {
        return DogeTx.targetFromBits(bits) ;
    }

    function concatHashPublic(uint tx1, uint tx2) public pure returns (uint) {
        return DogeTx.concatHash(tx1, tx2);
    }

    function flip32BytesPublic(uint input) public pure returns (uint) {
        return DogeTx.flip32Bytes(input);
    }

    function checkAuxPoWPublic(uint blockHash, bytes auxBytes) public view returns (uint) {
        return checkAuxPoWForTests(blockHash, auxBytes);
    }

    // doesn't check merge mining to see if other error codes work
    function checkAuxPoWForTests(uint _blockHash, bytes memory _auxBytes) internal view returns (uint) {
        DogeTx.AuxPoW memory ap = DogeTx.parseAuxPoW(_auxBytes, 0, _auxBytes.length);

        //uint32 version = bytesToUint32Flipped(_auxBytes, 0);

        if (!DogeTx.isMergeMined(_auxBytes, 0)) {
            return ERR_NOT_MERGE_MINED;
        }

        if (ap.coinbaseTxIndex != 0) {
            return ERR_COINBASE_INDEX;
        }

        if (ap.coinbaseMerkleRootCode != 1) {
            return ap.coinbaseMerkleRootCode;
        }

        if (DogeTx.computeChainMerkle(_blockHash, ap) != ap.coinbaseMerkleRoot) {
            return ERR_CHAIN_MERKLE;
        }

        if (DogeTx.computeParentMerkle(ap) != ap.parentMerkleRoot) {
            return ERR_PARENT_MERKLE;
        }

        return 1;
    }

    // @dev - Converts a bytes of size 4 to uint32,
    // e.g. for input [0x01, 0x02, 0x03 0x04] returns 0x01020304
    function bytesToUint32(bytes memory input, uint pos) internal pure returns (uint32 result) {
        result = uint32(input[pos])*(2**24) + uint32(input[pos + 1])*(2**16) + uint32(input[pos + 2])*(2**8) + uint32(input[pos + 3]);
    }

    // @dev converts bytes of any length to bytes32.
    // If `_rawBytes` is longer than 32 bytes, it truncates to the 32 leftmost bytes.
    // If it is shorter, it pads with 0s on the left.
    // Should be private, made internal for testing
    //
    // @param _rawBytes - arbitrary length bytes
    // @return - leftmost 32 or less bytes of input value; padded if less than 32
    function bytesToBytes32(bytes _rawBytes, uint pos) internal pure returns (bytes32) {
        bytes32 out;
        assembly {
            out := mload(add(add(_rawBytes, 0x20), pos))
        }
        return out;
    }

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

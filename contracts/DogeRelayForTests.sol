pragma solidity ^0.4.19;

import "./DogeRelay.sol";
import "./DogeParser/DogeTx.sol";

contract DogeRelayForTests is DogeRelay {

    function DogeRelayForTests(Network network) public DogeRelay(network) {}

    function bytesToUint32Public(bytes memory input) public pure returns (uint32 result) {
        return bytesToUint32(input, 0);
    }

    function bytesToBytes32Public(bytes b) public pure returns (bytes32) {
        return bytesToBytes32(b, 0);
    }

    function sliceArrayPublic(bytes original, uint32 offset, uint32 endIndex) public view returns (bytes result) {
        return DogeTx.sliceArray(original, offset, endIndex);
    }

    function getBlockHash(uint blockHeight) public view returns (uint) {
        return fastGetBlockHash(blockHeight);
    }


    // return the chainWork of the Tip
    // http://bitcoin.stackexchange.com/questions/26869/what-is-chainwork
    function getChainWork() public view returns (uint128) {
        return getScore(bestBlockHash);
    }


    // return the difference between the chainWork at
    // the blockchain Tip and its 10th ancestor
    //
    // this is not needed by the relay itself, but is provided in
    // case some contract wants to use the chainWork or Bitcoin network
    // difficulty (which can be derived) as a data feed for some purpose
    function getAverageChainWork() public view returns (uint) {
        uint blockHash = bestBlockHash;

        uint128 chainWorkTip = getScore(blockHash);

        uint8 i = 0;
        while (i < 10) {
            blockHash = getPrevBlock(blockHash);
            i += 1;
        }

        // uint128 chainWork10Ancestors = getScore(blockHash);

        return (chainWorkTip - getScore(blockHash));
    }

    // returns the block header (zeros for a header that does not exist) when
    // sufficient payment is provided.  If payment is insufficient, returns 1-byte of zero.
    function getBlockHeader(uint blockHash) internal returns (BlockHeader) {
        // TODO: incentives
        // if (feePaid(blockHash, m_getFeeAmount(blockHash))) {  // in incentive.se
        //     GetHeader (blockHash, 0);
        //    return(text("\x00"):str);
        // }
        GetHeader(bytes32(blockHash), 1);
        return myblocks[blockHash]._blockHeader;
    }

    function getPrevBlockPublic(uint blockHash) public view returns (uint) {
        return getPrevBlock(blockHash);
    }

    function getTimestampPublic(uint blockHash) public view returns (uint32 result) {
        return getTimestamp(blockHash);
    }

    function getBitsPublic(uint blockHash) public view returns (uint32 result) {
        return getBits(blockHash);
    }

    function targetFromBitsPublic(uint32 bits) public pure returns (uint) {
        return targetFromBits(bits) ;
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
}

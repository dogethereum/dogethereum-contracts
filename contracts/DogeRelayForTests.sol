pragma solidity ^0.4.19;

import "./DogeRelay.sol";

contract DogeRelayForTests is DogeRelay {

    function DogeRelayForTests(Network network) public DogeRelay(network) {}

    function bytesToUint32Public(bytes memory input) public pure returns (uint32 result) {
        return bytesToUint32(input);
    }

    function bytesToBytes32Public(bytes b) public pure returns (bytes32) {
        return bytesToBytes32(b);
    }

    function sliceArrayPublic(bytes original, uint32 offset, uint32 endIndex) public view returns (bytes result) {
        return sliceArray(original, offset, endIndex);
    }

    function getBlockHash(uint blockHeight) public view returns (uint) {
        return priv_fastGetBlockHash__(blockHeight);
    }


    // return the chainWork of the Tip
    // http://bitcoin.stackexchange.com/questions/26869/what-is-chainwork
    function getChainWork() public view returns (uint128) {
        return m_getScore(bestBlockHash);
    }


    // return the difference between the chainWork at
    // the blockchain Tip and its 10th ancestor
    //
    // this is not needed by the relay itself, but is provided in
    // case some contract wants to use the chainWork or Bitcoin network
    // difficulty (which can be derived) as a data feed for some purpose
    function getAverageChainWork() public view returns (uint) {
        uint blockHash = bestBlockHash;

        uint128 chainWorkTip = m_getScore(blockHash);

        uint8 i = 0;
        while (i < 10) {
            blockHash = getPrevBlock(blockHash);
            i += 1;
        }

        // uint128 chainWork10Ancestors = m_getScore(blockHash);

        return (chainWorkTip - m_getScore(blockHash));
    }

    // returns the block header (zeros for a header that does not exist) when
    // sufficient payment is provided.  If payment is insufficient, returns 1-byte of zero.
    function getBlockHeader(uint blockHash) public returns (bytes) {
        // TODO: incentives
        // if (feePaid(blockHash, m_getFeeAmount(blockHash))) {  // in incentive.se
        //     GetHeader (blockHash, 0);
        //    return(text("\x00"):str);
        // }
        GetHeader(blockHash, 1);
        return myblocks[blockHash]._blockHeader;
    }

    function getPrevBlockPublic(uint blockHash) public view returns (uint) {
        return getPrevBlock(blockHash);
    }

    function m_getTimestampPublic(uint blockHash) public view returns (uint32 result) {
        return m_getTimestamp(blockHash);
    }

    function m_getBitsPublic(uint blockHash) public view returns (uint32 result) {
        return m_getBits(blockHash);
    }


    function targetFromBitsPublic(uint32 bits) public pure returns (uint) {
        return targetFromBits(bits) ;
    }

    function concatHashPublic(uint tx1, uint tx2) public pure returns (uint) {
        return concatHash(tx1, tx2);
    }

    function flip32BytesPublic(uint input) public pure returns (uint) {
        return flip32Bytes(input);
    }
}

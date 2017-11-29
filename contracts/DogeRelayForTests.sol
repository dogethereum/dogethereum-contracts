pragma solidity ^0.4.15;
import "./DogeRelay.sol";

contract DogeRelayForTests is DogeRelay {
  function bytesToBytes32Public(bytes b) public pure returns (bytes32) {
    return bytesToBytes32(b);
  }

  function sliceArrayPublic(bytes original, uint32 offset, uint32 endIndex) public pure returns (bytes result) {
    return sliceArray(original, offset, endIndex);
  }

  // return the hash of the heaviest block aka the Tip
  function getBestBlockHash() public view returns (uint) {
    return bestBlockHash;
  }

  // return the height of the best block aka the Tip
  function getBestBlockHeight() public view returns (uint) {
    return m_getHeight(bestBlockHash);
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
  function getAverageChainWork() returns (uint) {
      uint blockHash = bestBlockHash;

      uint128 chainWorkTip = m_getScore(blockHash);

      uint8 i = 0;
      while (i < 10) {
          blockHash = getPrevBlock(blockHash);
          i += 1;
      }

      uint128 chainWork10Ancestors = m_getScore(blockHash);

      return (chainWorkTip - chainWork10Ancestors);
  }

	// returns the 80-byte header (zeros for a header that does not exist) when
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



}

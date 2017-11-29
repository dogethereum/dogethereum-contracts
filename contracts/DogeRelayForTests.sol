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

}

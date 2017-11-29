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


}

pragma solidity ^0.4.15;
import "./DogeRelay.sol";

contract DogeRelayForTests is DogeRelay {
  function bytesToBytes32Public(bytes b) public pure returns (bytes32) {
  	return super.bytesToBytes32(b);
  }

}

pragma solidity ^0.4.19;

interface IDogeRelay {
    function scryptVerified(bytes32 _requestId) public returns (uint);
}

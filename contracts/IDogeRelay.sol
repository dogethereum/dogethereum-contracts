pragma solidity ^0.4.19;

interface IDogeRelay {
    function scryptVerified(bytes32 _proposalId) public returns (uint);
}

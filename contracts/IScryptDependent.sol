pragma solidity ^0.4.19;

interface IScryptDependent {
    function scryptVerified(bytes32 _proposalId) public returns (uint);
}

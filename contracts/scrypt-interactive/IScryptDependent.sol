pragma solidity ^0.4.4;

interface IScryptDependent {
    function scryptSubmitted(bytes32 _proposalId, bytes32 _scryptHash, bytes _data, address _submitter) external;
    function scryptVerified(bytes32 _proposalId) external;
    function scryptFailed(bytes32 _proposalId) external;
}

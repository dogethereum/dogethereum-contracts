pragma solidity ^0.4.19;

interface IScryptCheckerListener {
    // @dev Scrypt verification succeeded
    function scryptVerified(bytes32 _proposalId) external returns (uint);

    // @dev Scrypt verification failed
    function scryptFailed(bytes32 _proposalId) external returns (uint);
}

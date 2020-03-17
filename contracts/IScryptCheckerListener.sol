pragma solidity 0.5.16;

interface IScryptCheckerListener {
    // @dev Scrypt verification submitted
    function scryptSubmitted(bytes32 _proposalId, bytes32 _scryptHash, bytes calldata _data, address _submitter) external;

    // @dev Scrypt verification succeeded
    function scryptVerified(bytes32 _proposalId) external;

    // @dev Scrypt verification failed
    function scryptFailed(bytes32 _proposalId) external;
}

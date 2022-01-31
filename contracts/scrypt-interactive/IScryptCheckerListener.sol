// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface IScryptCheckerListener {
    // @dev Scrypt verification submitted
    function scryptSubmitted(
        bytes32 proposalId,
        bytes32 scryptHash,
        bytes memory data,
        address submitter
    ) external;

    // @dev Scrypt verification succeeded
    function scryptVerified(bytes32 proposalId) external;

    // @dev Scrypt verification failed
    function scryptFailed(bytes32 proposalId) external;
}

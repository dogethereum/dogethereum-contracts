// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
import './ScryptClaims.sol';
import './IScryptCheckerListener.sol';

contract DogeRelayDummy is IScryptCheckerListener {

    ScryptClaims scryptClaims;

    event ScryptSubmitted(bytes32 proposalId, bytes32 scryptHash, bytes data, address submitter);
    event ScryptVerified(bytes32 proposalId);
    event ScryptFailed(bytes32 proposalId);

    constructor(ScryptClaims _scryptClaims) {
        scryptClaims = _scryptClaims;
    }

    function scryptVerified(bytes32 proposalId) external override {
        emit ScryptVerified(proposalId);
    }

    function scryptSubmitted(bytes32 proposalId, bytes32 scryptHash, bytes memory data, address submitter) external override {
        emit ScryptSubmitted(proposalId, scryptHash, data, submitter);
    }

    function scryptFailed(bytes32 proposalId) external override {
        emit ScryptFailed(proposalId);
    }
}

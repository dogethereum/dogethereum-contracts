// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import './IScryptCheckerListener.sol';

interface IScryptChecker {
    // Check a scrypt was calculated correctly from a plaintext.
    // @param data Data used to calculate scrypt hash.
    // @param hash Result of applying scrypt to data.
    // @param proposalId Id of the proposal.
    // @param scryptDependent Contract to notify resolution of the check.
    function checkScrypt(bytes memory data, bytes32 hash, bytes32 proposalId, IScryptCheckerListener scryptCheckerListener) external payable;
}

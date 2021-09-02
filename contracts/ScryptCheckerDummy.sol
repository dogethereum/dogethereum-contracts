// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import {IScryptCheckerListener} from "./scrypt-interactive/IScryptCheckerListener.sol";
import {IScryptChecker} from "./scrypt-interactive/IScryptChecker.sol";

contract ScryptCheckerDummy is IScryptChecker {
    // Accept all checks
    bool public acceptAll;

    // Mapping from keccak(data) to scryptHash(data)
    mapping (bytes32 => bytes32) public hashStorage;

    struct ScryptHashRequest {
        bytes data;
        bytes32 hash;
        address submitter;
        bytes32 id;
    }

    // Mapping scryptHash => request
    mapping (bytes32 => ScryptHashRequest) public pendingRequests;


    constructor(bool initAcceptAll) {
        acceptAll = initAcceptAll;
    }

    // Mark to accept hash as the scrypt hash of data
    function storeScryptHash(bytes calldata data, bytes32 hash) public {
        hashStorage[keccak256(data)] = hash;
    }

    // Check a scrypt was calculated correctly from a plaintext.
    // @param data – data used to calculate scrypt hash.
    // @param hash – result of applying scrypt to data.
    // @param submitter – the address of the submitter.
    // @param requestId – request identifier of the call.
    function checkScrypt(bytes calldata data, bytes32 hash, bytes32 proposalId, IScryptCheckerListener scryptDependent) override external payable {
        if (acceptAll || hashStorage[keccak256(data)] == hash) {
            scryptDependent.scryptSubmitted(proposalId, hash, data, msg.sender);
            scryptDependent.scryptVerified(proposalId);
        } else {
            pendingRequests[hash] = ScryptHashRequest({
                data: data,
                hash: hash,
                submitter: msg.sender,
                id: proposalId
            });
            scryptDependent.scryptSubmitted(proposalId, hash, data, msg.sender);
        }
    }

    function sendVerification(bytes32 hash, IScryptCheckerListener scryptDependent) public {
        ScryptHashRequest storage request = pendingRequests[hash];
        require(request.hash == hash);
        scryptDependent.scryptVerified(request.id);
    }

    function sendFailed(bytes32 hash, IScryptCheckerListener scryptDependent) public {
        ScryptHashRequest storage request = pendingRequests[hash];
        require(request.hash == hash);
        scryptDependent.scryptFailed(request.id);
    }
}

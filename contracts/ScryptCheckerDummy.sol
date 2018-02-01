pragma solidity ^0.4.19;

import "./IScryptDependent.sol";
import "./IScryptChecker.sol";

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
        IScryptDependent scryptDependent;
    }

    // Mapping scryptHash => request
    mapping (bytes32 => ScryptHashRequest) public pendingRequests;


    function ScryptCheckerDummy(bool _acceptAll) public {
        acceptAll = _acceptAll;
    }

    // Mark to accept _hash as the scrypt hash of _data
    function storeScryptHash(bytes _data, bytes32 _hash) public {
        hashStorage[keccak256(_data)] = _hash;
    }

    // Check a scrypt was calculated correctly from a plaintext.
    // @param _data – data used to calculate scrypt hash.
    // @param _hash – result of applying scrypt to data.
    // @param _submitter – the address of the submitter.
    // @param _requestId – request identifier of the call.
    function checkScrypt(bytes _data, bytes32 _hash, bytes32 _proposalId, IScryptDependent _scryptDependent) public payable {
        if (acceptAll || hashStorage[keccak256(_data)] == _hash) {
            IScryptDependent(_scryptDependent).scryptVerified(_proposalId);
        } else {
            pendingRequests[_hash] = ScryptHashRequest({
                data: _data,
                hash: _hash,
                submitter: tx.origin,
                id: _proposalId,
                scryptDependent: _scryptDependent
            });
        }
    }

    function sendVerification(bytes32 _hash) public {
        ScryptHashRequest storage request = pendingRequests[_hash];
        require(request.hash == _hash);
        IScryptDependent(request.scryptDependent).scryptVerified(request.id);
    }
}

pragma solidity 0.5.16;

import {IScryptCheckerListener} from "./IScryptCheckerListener.sol";
import {IScryptChecker} from "./IScryptChecker.sol";

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


    constructor(bool _acceptAll) public {
        acceptAll = _acceptAll;
    }

    // Mark to accept _hash as the scrypt hash of _data
    function storeScryptHash(bytes memory _data, bytes32 _hash) public {
        hashStorage[keccak256(_data)] = _hash;
    }

    // Check a scrypt was calculated correctly from a plaintext.
    // @param _data – data used to calculate scrypt hash.
    // @param _hash – result of applying scrypt to data.
    // @param _submitter – the address of the submitter.
    // @param _requestId – request identifier of the call.
    function checkScrypt(bytes calldata _data, bytes32 _hash, bytes32 _proposalId, IScryptCheckerListener _scryptDependent) external payable {
        if (acceptAll || hashStorage[keccak256(_data)] == _hash) {
            _scryptDependent.scryptSubmitted(_proposalId, _hash, _data, msg.sender);
            _scryptDependent.scryptVerified(_proposalId);
        } else {
            pendingRequests[_hash] = ScryptHashRequest({
                data: _data,
                hash: _hash,
                submitter: msg.sender,
                id: _proposalId
            });
            _scryptDependent.scryptSubmitted(_proposalId, _hash, _data, msg.sender);
        }
    }

    function sendVerification(bytes32 _hash, IScryptCheckerListener _scryptDependent) public {
        ScryptHashRequest storage request = pendingRequests[_hash];
        require(request.hash == _hash);
        _scryptDependent.scryptVerified(request.id);
    }

    function sendFailed(bytes32 _hash, IScryptCheckerListener _scryptDependent) public {
        ScryptHashRequest storage request = pendingRequests[_hash];
        require(request.hash == _hash);
        _scryptDependent.scryptFailed(request.id);
    }
}

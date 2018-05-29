pragma solidity ^0.4.19;

import {IScryptCheckerListener} from "./IScryptCheckerListener.sol";
import {IScryptChecker} from "./IScryptChecker.sol";

contract ScryptCheckerDummy is IScryptChecker {
    // DogeRelay
    IScryptCheckerListener public dogeRelay;

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


    constructor(IScryptCheckerListener _dogeRelay, bool _acceptAll) public {
        dogeRelay = _dogeRelay;
        acceptAll = _acceptAll;
    }

    function setDogeRelay(IScryptCheckerListener _dogeRelay) public {
      require(address(dogeRelay) == 0);
      dogeRelay = _dogeRelay;
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
    function checkScrypt(bytes _data, bytes32 _hash, bytes32 _proposalId, address _submitter) external payable {
        if (acceptAll || hashStorage[keccak256(_data)] == _hash) {
            dogeRelay.scryptVerified(_proposalId);
        } else {
            pendingRequests[_hash] = ScryptHashRequest({
                data: _data,
                hash: _hash,
                submitter: _submitter,
                id: _proposalId
            });
        }
    }

    function sendVerification(bytes32 _hash) public {
        ScryptHashRequest storage request = pendingRequests[_hash];
        require(request.hash == _hash);
        dogeRelay.scryptVerified(request.id);
    }

    function sendFailed(bytes32 _hash) public {
        ScryptHashRequest storage request = pendingRequests[_hash];
        require(request.hash == _hash);
        dogeRelay.scryptFailed(request.id);
    }
}

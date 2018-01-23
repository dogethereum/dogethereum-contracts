pragma solidity ^0.4.19;

import "./IDogeRelay.sol";

contract ScryptCheckerDummy {
    // DogeRelay
    IDogeRelay public dogeRelay;

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


    function ScryptCheckerDummy(address _dogeRelay, bool _acceptAll) public {
        dogeRelay = IDogeRelay(_dogeRelay);
        acceptAll = _acceptAll;
    }

    function setDogeRelay(address _dogeRelay) public {
      require(address(dogeRelay) == 0);
      dogeRelay = IDogeRelay(_dogeRelay);
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
    function checkScrypt(bytes _data, bytes32 _hash, address _submitter, bytes32 _requestId) public payable returns (uint) {
        if (acceptAll || hashStorage[keccak256(_data)] == _hash) {
            dogeRelay.scryptVerified(_requestId);
        } else {
            pendingRequests[_hash] = ScryptHashRequest({
                data: _data,
                hash: _hash,
                submitter: _submitter,
                id: _requestId
            });
        }
    }

    function sendVerification(bytes32 _hash) public {
        ScryptHashRequest storage request = pendingRequests[_hash];
        require(request.hash == _hash);
        dogeRelay.scryptVerified(request.id);
    }
}

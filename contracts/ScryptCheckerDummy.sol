pragma solidity ^0.4.19;

import {IScryptCheckerListener} from "./IScryptCheckerListener.sol";
import {IScryptChecker} from "./IScryptChecker.sol";

contract ScryptCheckerDummy is IScryptChecker {

    struct ScryptHashRequest {
        bytes data;
        bytes32 hash;
        address submitter;
        bytes32 id;
    }

    event DepositBonded(uint claimID, address account, uint amount);
    event DepositMade(address who, uint amount);

    event ClaimCreated(uint claimID, address claimant, bytes plaintext, bytes blockHash);
    event ClaimChallenged(uint claimID, address challenger);

    event VerificationGameStarted(uint claimID, address claimant, address challenger, uint sessionId);

    // Accept all checks
    bool public acceptAll;

    // Mapping from keccak(data) to scryptHash(data)
    mapping (bytes32 => bytes32) public hashStorage;

    // Mapping scryptHash => request
    mapping (bytes32 => ScryptHashRequest) public pendingRequests;


    constructor(bool _acceptAll) public {
        acceptAll = _acceptAll;
    }

    // Mark to accept _hash as the scrypt hash of _data
    function storeScryptHash(bytes _data, bytes32 _hash) public {
        hashStorage[keccak256(_data)] = _hash;
    }

    function makeDeposit() public payable returns (uint) {
        emit DepositMade(msg.sender, msg.value);
        return msg.value;
    }

    // Check a scrypt was calculated correctly from a plaintext.
    // @param _data – data used to calculate scrypt hash.
    // @param _hash – result of applying scrypt to data.
    // @param _submitter – the address of the submitter.
    // @param _requestId – request identifier of the call.
    function checkScrypt(bytes _data, bytes32 _hash, bytes32 _proposalId, IScryptCheckerListener _scryptDependent) external payable {
        uint claimID = 1;
        if (acceptAll || hashStorage[keccak256(_data)] == _hash) {
            _scryptDependent.scryptVerified(_proposalId);
        } else {
            pendingRequests[_hash] = ScryptHashRequest({
                data: _data,
                hash: _hash,
                submitter: msg.sender,
                id: _proposalId
            });
            emit DepositBonded(claimID, msg.sender, 1);
            //FIXME: hash parameter is wrong
            emit ClaimCreated(claimID, msg.sender, _data, _data);
        }
    }

    function challengeClaim(uint claimID) public {
        emit DepositBonded(claimID, msg.sender, 1);
        emit ClaimChallenged(claimID, msg.sender);
    }

    function runNextVerificationGame(uint claimID) public {
        emit VerificationGameStarted(claimID, msg.sender, msg.sender, 1);
    }

    function getSession(uint claimID, address challenger) public view returns(uint) {
        (claimID);
        (challenger);
        return 1;
    }

    /* function getSession(uint sessionId) public view returns (uint, uint, uint, bytes, bytes32) {
        (sessionId);
        return (0, 0, 0, new bytes(0), 0x0);
    } */

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

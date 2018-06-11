pragma solidity ^0.4.19;

import {IScryptCheckerListener} from "./IScryptCheckerListener.sol";

interface IScryptChecker {
    // Check a scrypt was calculated correctly from a plaintext.
    // @param _data – data used to calculate scrypt hash.
    // @param _hash – result of applying scrypt to data.
    // @param _reqid – request identifier of the call.
    // @param _submitter – the address of the submitter.
    // @param _listener - contract to notify resolution of the check.
    function checkScrypt(bytes _data, bytes32 _hash, bytes32 _proposalId, address _submitter, IScryptCheckerListener _listener) external payable;
}

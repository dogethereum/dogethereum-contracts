pragma solidity ^0.4.19;

interface IScryptChecker {
    // Check a scrypt was calculated correctly from a plaintext.
    // @param _data – data used to calculate scrypt hash.
    // @param _hash – result of applying scrypt to data.
    // @param _submitter – the address of the submitter.
    // @param _reqid – request identifier of the call.
    function checkScrypt(bytes _data, bytes32 _hash, address _submitter, bytes32 _proposalId) public payable;
}

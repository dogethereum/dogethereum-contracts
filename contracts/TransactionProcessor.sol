// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

// Interface contract to be implemented by DogeToken
contract TransactionProcessor {
    function processTransaction(bytes txn, uint txHash, bytes20 operatorPublicKeyHash, address superblockSubmitterAddress) public returns (uint);
}

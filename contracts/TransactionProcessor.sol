// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

// Interface contract to be implemented by DogeToken
abstract contract TransactionProcessor {
    function processTransaction(bytes calldata txn, uint txHash, bytes20 operatorPublicKeyHash, address superblockSubmitterAddress) virtual public returns (uint);
}

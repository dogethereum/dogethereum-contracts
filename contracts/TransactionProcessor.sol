// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

// Interface contract to be implemented by DogeToken
abstract contract TransactionProcessor {
    function processLockTransaction(
        bytes calldata txn,
        uint txHash,
        bytes20 operatorPublicKeyHash,
        address superblockSubmitterAddress
    ) virtual public;
    function processUnlockTransaction(
        bytes calldata txn,
        uint txHash,
        bytes20 operatorPublicKeyHash,
        address superblockSubmitterAddress
    ) virtual public;
    function processReportOperatorFreeUtxoSpend(
        bytes calldata txn,
        uint txHash,
        bytes20 operatorPublicKeyHash,
        uint32 operatorTxOutputReference,
        uint32 unlawfulTxInputIndex
    ) virtual public;
}

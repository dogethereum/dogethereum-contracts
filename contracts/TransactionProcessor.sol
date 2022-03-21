// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

// Interface contract to be implemented by DogeToken
abstract contract TransactionProcessor {
  function processLockTransaction(
    bytes calldata txn,
    uint256 txHash,
    bytes20 operatorPublicKeyHash,
    address superblockSubmitterAddress
  ) public virtual;

  function processUnlockTransaction(
    bytes calldata txn,
    uint256 txHash,
    bytes20 operatorPublicKeyHash,
    uint256 unlockIndex
  ) public virtual;

  function processReportOperatorFreeUtxoSpend(
    bytes calldata txn,
    uint256 txHash,
    bytes20 operatorPublicKeyHash,
    uint32 operatorTxOutputReference,
    uint32 unlawfulTxInputIndex
  ) public virtual;
}

// SPDX-License-Identifier: MIT

/*
Example contract that can process Doge transactions relayed to it via
DogeSuperblocks. This stores the Doge transaction hash and the Ethereum block
number (so people running the same example with the same Doge transaction
can get an indication that the storage was indeed updated).
*/
pragma solidity ^0.7.6;

import "./TransactionProcessor.sol";
import "hardhat/console.sol";

contract DummyTransactionProcessor is TransactionProcessor {
  uint256 public lastTxHash;
  uint256 public ethBlock;

  address private trustedRelayerContract;

  constructor(address initRelayerContract) {
    trustedRelayerContract = initRelayerContract;
  }

  // processLockTransaction should avoid returning the same
  // value as ERR_RELAY_VERIFY (in constants.se) to avoid confusing callers
  //
  // @param bytes - doge tx
  // @param txHash - doge tx hash
  // @param bytes20 - public key hash of the operator
  // @param address - superblock submitter address
  // @return uint - number of satoshidoges locked in case of a valid lock tx, 0 in any other case.
  function processLockTransaction(
    bytes calldata,
    uint256 txHash,
    bytes20,
    address
  ) public override {
    console.log("processLockTransaction called");

    // only allow trustedRelayerContract, otherwise anyone can provide a fake dogeTx
    if (msg.sender == trustedRelayerContract) {
      console.log("processLockTransaction txHash, ");
      console.logBytes32(bytes32(txHash));
      ethBlock = block.number;
      lastTxHash = txHash;
      // parse & do whatever with dogeTx
      // For example, you should probably check if txHash has already
      // been processed, to prevent replay attacks.
      return;
    }

    console.log("processLockTransaction failed");
  }

  // processUnlockTransaction should avoid returning the same
  // value as ERR_RELAY_VERIFY (in constants.se) to avoid confusing callers
  //
  // @param bytes - doge tx
  // @param txHash - doge tx hash
  // @param bytes20 - public key hash of the operator
  // @param uint256 - Index of the unlock request
  // @return uint - number of satoshidoges locked in case of a valid lock tx, 0 in any other case.
  function processUnlockTransaction(
    bytes calldata,
    uint256 txHash,
    bytes20,
    uint256
  ) public override {
    console.log("processUnlockTransaction called");

    // only allow trustedRelayerContract, otherwise anyone can provide a fake dogeTx
    if (msg.sender == trustedRelayerContract) {
      console.log("processUnlockTransaction txHash, ");
      console.logBytes32(bytes32(txHash));
      ethBlock = block.number;
      lastTxHash = txHash;
      // parse & do whatever with dogeTx
      // For example, you should probably check if txHash has already
      // been processed, to prevent replay attacks.
      return;
    }

    console.log("processUnlockTransaction failed");
  }

  function processReportOperatorFreeUtxoSpend(
    bytes calldata, /*txn*/
    uint256 txHash,
    bytes20, /*operatorPublicKeyHash*/
    uint32, /*operatorTxOutputReference*/
    uint32 /*unlawfulTxInputIndex*/
  ) public override {
    console.log("processReportOperatorFreeUtxoSpend called");

    // only allow trustedRelayerContract, otherwise anyone can provide a fake dogeTx
    if (msg.sender == trustedRelayerContract) {
      console.log("processReportOperatorFreeUtxoSpend txHash, ");
      console.logBytes32(bytes32(txHash));
      ethBlock = block.number;
      lastTxHash = txHash;
      // parse & do whatever with dogeTx
      // For example, you should probably check if txHash has already
      // been processed, to prevent replay attacks.
      return;
    }

    console.log("processReportOperatorFreeUtxoSpend failed");
  }
}

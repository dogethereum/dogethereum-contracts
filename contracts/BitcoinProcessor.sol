/*
Example contract that can process Bitcoin transactions relayed to it via
BTC Relay.  This stores the Bitcoin transaction hash and the Ethereum block
number (so people running the same example with the same Bitcoin transaction
can get an indication that the storage was indeed updated).
*/
pragma solidity ^0.4.15;

import "./TransactionProcessor.sol";

contract BitcoinProcessor is TransactionProcessor {
    uint256 public lastTxHash;
    uint256 public ethBlock;

    address private _trustedBTCRelay;

    function BitcoinProcessor(address trustedBTCRelay) {
        _trustedBTCRelay = trustedBTCRelay;
    }

    // processTransaction should avoid returning the same
    // value as ERR_RELAY_VERIFY (in constants.se) to avoid confusing callers
    //
    // this exact function signature is required as it has to match
    // the signature specified in BTCRelay (otherwise BTCRelay will not call it)
    function processTransaction(bytes txn, uint256 txHash) returns (uint) {
        log0("processTransaction called");

        // only allow trustedBTCRelay, otherwise anyone can provide a fake txn
        if (msg.sender == _trustedBTCRelay) {
            log1("processTransaction txHash, ", bytes32(txHash));
            ethBlock = block.number;
            lastTxHash = txHash;
            // parse & do whatever with txn
            // For example, you should probably check if txHash has already
            // been processed, to prevent replay attacks.
            return 1;
        }

        log0("processTransaction failed");
        return 0;
    }
}

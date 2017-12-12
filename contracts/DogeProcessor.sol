/*
Example contract that can process Doge transactions relayed to it via
DogeRelay.  This stores the Doge transaction hash and the Ethereum block
number (so people running the same example with the same Doge transaction
can get an indication that the storage was indeed updated).
*/
pragma solidity ^0.4.19;

import "./TransactionProcessor.sol";

contract DogeProcessor is TransactionProcessor {
    uint256 public lastTxHash;
    uint256 public ethBlock;

    address private _trustedDogeRelay;

    function DogeProcessor(address trustedDogeRelay) public {
        _trustedDogeRelay = trustedDogeRelay;
    }

    // processTransaction should avoid returning the same
    // value as ERR_RELAY_VERIFY (in constants.se) to avoid confusing callers
    //
    // this exact function signature is required as it has to match
    // the signature specified in DogeRelay (otherwise DogeRelay will not call it)
    function processTransaction(bytes dogeTx, uint256 txHash) public returns (uint) {
        log0("processTransaction called");

        // only allow trustedDogeRelay, otherwise anyone can provide a fake dogeTx
        if (msg.sender == _trustedDogeRelay) {
            log1("processTransaction txHash, ", bytes32(txHash));
            ethBlock = block.number;
            lastTxHash = txHash;
            // parse & do whatever with dogeTx
            // For example, you should probably check if txHash has already
            // been processed, to prevent replay attacks.
            return 1;
        }

        log0("processTransaction failed");
        return 0;
    }
}

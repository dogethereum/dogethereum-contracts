/*
Example contract that can process Doge transactions relayed to it via
DogeSuperblocks. This stores the Doge transaction hash and the Ethereum block
number (so people running the same example with the same Doge transaction
can get an indication that the storage was indeed updated).
*/
pragma solidity 0.5.16;

import "./TransactionProcessor.sol";

contract DummyTransactionProcessor is TransactionProcessor {
    uint256 public lastTxHash;
    uint256 public ethBlock;

    address private _trustedRelayerContract;

    constructor(address trustedRelayerContract) public {
        _trustedRelayerContract = trustedRelayerContract;
    }

    // processTransaction should avoid returning the same
    // value as ERR_RELAY_VERIFY (in constants.se) to avoid confusing callers
    //
    // this exact function signature is required as it has to match
    // the signature specified in DogeSuperblocks (otherwise DogeSuperblocks will not call it)
    function processTransaction(bytes memory /* dogeTx */, uint256 txHash, bytes20 /* operatorPublicKeyHash */, address /* superblockSubmitterAddress */) public returns (uint) {
        log0("processTransaction called");

        // only allow trustedRelayerContract, otherwise anyone can provide a fake dogeTx
        if (msg.sender == _trustedRelayerContract) {
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

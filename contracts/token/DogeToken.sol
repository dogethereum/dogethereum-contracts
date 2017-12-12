
import "./HumanStandardToken.sol";
import "./Set.sol";
import "./../TransactionProcessor.sol";

pragma solidity ^0.4.8;

contract DogeToken is HumanStandardToken(0, "DogeToken", 8, "DOGETOKEN"), TransactionProcessor {

    address private _trustedDogeRelay;

    Set.Data dogeTxHashesAlreadyProcessed;
    uint256 minimumLockTxValue;

    function DogeToken(address trustedDogeRelay) public {
        _trustedDogeRelay = trustedDogeRelay;
        minimumLockTxValue = 100000000;
    }

    function processTransaction(bytes dogeTx, uint256 txHash) public returns (uint) {
        address harcodedDestinationAddress = 0xcedacadacafe;

        log0("processTransaction called");
        // Check tx was not processes already and add it to the dogeTxHashesAlreadyProcessed
        require(Set.insert(dogeTxHashesAlreadyProcessed, txHash));
        // only allow trustedDogeRelay, otherwise anyone can provide a fake dogeTx
        require(msg.sender == _trustedDogeRelay);
        balances[harcodedDestinationAddress] += 150;
        log1("processTransaction txHash, ", bytes32(txHash));
        return 1;
    }

    struct DogeTransaction {
    }

    struct DogePartialMerkleTree {
    }


    function registerDogeTransaction(DogeTransaction dogeTx, DogePartialMerkleTree pmt, uint blockHeight) private {
        // Validate tx is valid and has enough confirmations, then assigns tokens to sender of the doge tx
    }

    function releaseDoge(uint256 _value) public {
        balances[msg.sender] -= _value;
        // Send the tokens back to the doge blockchain. 
    }
}

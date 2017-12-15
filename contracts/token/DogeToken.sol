pragma solidity ^0.4.8;

import "./HumanStandardToken.sol";
import "./Set.sol";
import "./../TransactionProcessor.sol";
import "../DogeParser/DogeTx.sol";

contract DogeToken is HumanStandardToken(0, "DogeToken", 8, "DOGETOKEN"), TransactionProcessor {

    address private _trustedDogeRelay;

    Set.Data dogeTxHashesAlreadyProcessed;
    uint256 minimumLockTxValue;

    function DogeToken(address trustedDogeRelay) public {
        _trustedDogeRelay = trustedDogeRelay;
        minimumLockTxValue = 100000000;
    }

    function processTransaction(bytes dogeTx, uint256 txHash) public returns (uint) {
        log0("processTransaction called");

        uint out1;
        bytes20 addr1;
        uint out2;
        bytes20 addr2;
        (out1, addr1, out2, addr2) = DogeTx.getFirstTwoOutputs(dogeTx);

        //FIXME: Use address from first input
        address destinationAddress = address(addr1);

        // Check tx was not processes already and add it to the dogeTxHashesAlreadyProcessed
        require(Set.insert(dogeTxHashesAlreadyProcessed, txHash));

        //FIXME: Modify test so we can uncomment this
        //only allow trustedDogeRelay, otherwise anyone can provide a fake dogeTx
        //require(msg.sender == _trustedDogeRelay);

        balances[destinationAddress] += out1;

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

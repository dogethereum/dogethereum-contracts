pragma solidity ^0.4.8;

import "./HumanStandardToken.sol";
import "./Set.sol";
import "./../TransactionProcessor.sol";
import "../DogeParser/DogeTx.sol";

contract DogeToken is HumanStandardToken(0, "DogeToken", 8, "DOGETOKEN"), TransactionProcessor {

    address private _trustedDogeRelay;

    Set.Data dogeTxHashesAlreadyProcessed;
    uint256 minimumLockTxValue;

    event NewToken(address indexed user, uint value);


    function DogeToken(address trustedDogeRelay) public {
        _trustedDogeRelay = trustedDogeRelay;
        minimumLockTxValue = 100000000;
    }

    function processTransaction(bytes dogeTx, uint256 txHash) public returns (uint) {
        require(msg.sender == _trustedDogeRelay);

        uint out;
        bytes20 addr;
        bytes32 pubKey;
        bool odd;
        //(out, addr, pubKey, odd) = DogeTx.parseTransaction(dogeTx);

        //FIXME: Accept a single output
        (out, addr,,) = DogeTx.getFirstTwoOutputs(dogeTx);

        //FIXME: Only accept funds to our address
        //require(addr1 == "");

        (pubKey, odd) = DogeTx.getFirstInputPubKey(dogeTx);
        address destinationAddress = DogeTx.pub2address(uint256(pubKey), odd);

        // Check tx was not processes already and add it to the dogeTxHashesAlreadyProcessed
        require(Set.insert(dogeTxHashesAlreadyProcessed, txHash));

        balances[destinationAddress] += out;
        NewToken(destinationAddress, out);

        return out;
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

pragma solidity ^0.4.8;

import "./HumanStandardToken.sol";
import "./Set.sol";
import "./../TransactionProcessor.sol";
import "../DogeParser/DogeTx.sol";

contract DogeToken is HumanStandardToken(0, "DogeToken", 8, "DOGETOKEN"), TransactionProcessor {

    address private _trustedDogeRelay;
    address private _recipientDogethereum;

    Set.Data dogeTxHashesAlreadyProcessed;
    uint256 minimumLockTxValue;

    event NewToken(address indexed user, uint value, address recipient);


    function DogeToken(address trustedDogeRelay, address recipientDogethereum) public {
        _trustedDogeRelay = trustedDogeRelay;
        _recipientDogethereum = recipientDogethereum;
        minimumLockTxValue = 100000000;
    }

    function processTransaction(bytes dogeTx, uint256 txHash) public returns (uint) {
        require(msg.sender == _trustedDogeRelay);

        uint value;
        bytes20 recipient;
        bytes32 pubKey;
        bool odd;
        (value, recipient, pubKey, odd) = DogeTx.parseTransaction(dogeTx);

        // Accept outputs to the dedicated address
        require(address(recipient) == _recipientDogethereum);

        // Check tx was not processes already and add it to the dogeTxHashesAlreadyProcessed
        require(Set.insert(dogeTxHashesAlreadyProcessed, txHash));

        // Calculate ethereum address from dogecoin public key
        address destinationAddress = DogeTx.pub2address(uint256(pubKey), odd);

        balances[destinationAddress] += value;
        NewToken(destinationAddress, value, address(recipient));

        return value;
    }

    function wasLockTxProcessed(uint txHash) public view returns (bool) {
        return Set.contains(dogeTxHashesAlreadyProcessed, txHash);
    }
}

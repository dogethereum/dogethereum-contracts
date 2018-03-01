pragma solidity ^0.4.8;

import "./HumanStandardToken.sol";
import "./Set.sol";
import "./../TransactionProcessor.sol";
import "../DogeParser/DogeTx.sol";

contract DogeToken is HumanStandardToken(0, "DogeToken", 8, "DOGETOKEN"), TransactionProcessor {

    address public _trustedDogeRelay;
    bytes20 public _recipientDogethereum;

    Set.Data dogeTxHashesAlreadyProcessed;
    uint256 public minimumLockTxValue;

    event NewToken(address indexed user, uint value);

    struct Utxo {
          uint value;
          uint txHash;
          uint16 index;
    }
    Utxo[] public utxos;


    function DogeToken(address trustedDogeRelay, bytes20 recipientDogethereum) public {
        _trustedDogeRelay = trustedDogeRelay;
        _recipientDogethereum = recipientDogethereum;
        minimumLockTxValue = 100000000;
    }

    function processTransaction(bytes dogeTx, uint txHash) public returns (uint) {
        require(msg.sender == _trustedDogeRelay);

        uint value;
        bytes32 pubKey;
        bool odd;
        uint16 outputIndex;
        (value, pubKey, odd, outputIndex) = DogeTx.parseTransaction(dogeTx, _recipientDogethereum);

        // Check tx was not processes already and add it to the dogeTxHashesAlreadyProcessed
        require(Set.insert(dogeTxHashesAlreadyProcessed, txHash));

        // Add utxo
        utxos.push(Utxo(value, txHash, outputIndex));

        // Calculate ethereum address from dogecoin public key
        address destinationAddress = DogeTx.pub2address(uint256(pubKey), odd);

        balances[destinationAddress] += value;
        NewToken(destinationAddress, value);
        // Hack to make etherscan show the event
        Transfer(0, destinationAddress, value);

        return value;
    }

    function wasLockTxProcessed(uint txHash) public view returns (bool) {
        return Set.contains(dogeTxHashesAlreadyProcessed, txHash);
    }

    // Unlock section begin

    // Request ERC20 tokens to be burnt and dogecoins be received on the doge blockchain
    function doUnlock(string dogeAddress, uint256 _value) public returns (bool success) {
        require(balances[msg.sender] >= _value);
        balances[msg.sender] -= _value;
        // Hack to make etherscan show the event
        Transfer(msg.sender, 0, _value);
        ++unlockIdx;
        UnlockRequest(unlockIdx, msg.sender, dogeAddress, _value, block.timestamp);
        unlocksPendingInvestorProof[unlockIdx] = Unlock(unlockIdx, msg.sender, dogeAddress, _value, block.timestamp);
        Set.insert(unlocksPendingInvestorProofKeySet, unlockIdx);
        return true;
    }

    // Represents an unlock request
    struct Unlock {
          uint id;
          address _from;
          string dogeAddress;
          uint _value;
          uint timestamp;
    }

    // counter for next unlock
    uint internal unlockIdx;

    // Unlocks the investor has not sent a proof of unlock yet.
    mapping (uint => Unlock) unlocksPendingInvestorProof;
    // Set with keys of unlocksPendingInvestorProof.
    Set.Data unlocksPendingInvestorProofKeySet;

    event UnlockRequest(uint id, address from, string dogeAddress, uint value, uint timestamp);

    // Unlock section end
}

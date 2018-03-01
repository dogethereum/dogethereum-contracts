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
    uint nextUnspentUtxoIndex;


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
    function doUnlock(string dogeAddress, uint value) public returns (bool success) {
        require(balances[msg.sender] >= value);
        balances[msg.sender] -= value;
        uint[] memory selectedUtxos;
        uint fee;
        (selectedUtxos, fee) = selectUtxosAndFee(value);
        // Hack to make etherscan show the event
        Transfer(msg.sender, 0, value);
        ++unlockIdx;
        UnlockRequest(unlockIdx, msg.sender, dogeAddress, value, block.timestamp);
        unlocksPendingInvestorProof[unlockIdx] = Unlock(unlockIdx, msg.sender, dogeAddress, value, 
                                                        block.timestamp, selectedUtxos, fee);

        Set.insert(unlocksPendingInvestorProofKeySet, unlockIdx);
        return true;
    }

    uint constant MIN_FEE = 100000000;
    uint constant BASE_FEE = 50000000;
    uint constant FEE_PER_INPUT = 100000000;

    function selectUtxosAndFee(uint valueToSend) private returns (uint[] memory selectedUtxos, uint fee) {
        // There should be at least 1 utxo available
        require(nextUnspentUtxoIndex < utxos.length);
        fee = BASE_FEE;
        uint selectedUtxosValue;
        uint i;
        while (selectedUtxosValue < (valueToSend + fee) && (nextUnspentUtxoIndex < utxos.length)) {
            selectedUtxosValue += utxos[nextUnspentUtxoIndex].value;
            fee += FEE_PER_INPUT;
            selectedUtxos[i] = nextUnspentUtxoIndex;
            nextUnspentUtxoIndex++;
            i++;
        }
        require(selectedUtxosValue < (valueToSend + fee));
        return (selectedUtxos, fee);
    }


    // Represents an unlock request
    struct Unlock {
          uint id;
          address from;
          string dogeAddress;
          uint value;
          uint timestamp;
          // Values are indexes in storage array "utxos"
          uint[] selectedUtxos;
          uint fee;
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

pragma solidity ^0.4.8;

import "./HumanStandardToken.sol";
import "./Set.sol";
import "./../TransactionProcessor.sol";
import "../DogeParser/DogeTx.sol";
import "./../ECRecovery.sol";

contract DogeToken is HumanStandardToken(0, "DogeToken", 8, "DOGETOKEN"), TransactionProcessor {

    // Constants
    uint public constant MIN_LOCK_VALUE = 150000000; // 1.5 doges
    uint public constant MIN_UNLOCK_VALUE = 300000000; // 3 doges
    uint constant MIN_FEE = 100000000; // 1 doge
    uint constant BASE_FEE = 50000000; // 0.5 doge
    uint constant FEE_PER_INPUT = 100000000; // 1 doge

    // Error codes
    uint constant ERR_OPERATOR_SIGNATURE = 60010;
    uint constant ERR_OPERATOR_ALREADY_CREATED = 60015;
    uint constant ERR_OPERATOR_NOT_CREATED_OR_WRONG_SENDER = 60020;
    uint constant ERR_OPERATOR_HAS_BALANCE = 60030;
    uint constant ERR_OPERATOR_WITHDRAWAL_NOT_ENOUGH_BALANCE = 60040;
    uint constant ERR_OPERATOR_WITHDRAWAL_COLLATERAL_WOULD_BE_TOO_LOW = 60050;
    uint constant ERR_PROCESS_OPERATOR_NOT_CREATED = 60060;
    uint constant ERR_PROCESS_TX_ALREADY_PROCESSED = 60070;
    uint constant ERR_UNLOCK_MIN_UNLOCK_VALUE = 60080;
    uint constant ERR_UNLOCK_USER_BALANCE = 60090;
    uint constant ERR_UNLOCK_OPERATOR_NOT_CREATED = 60100;
    uint constant ERR_UNLOCK_OPERATOR_BALANCE = 60110;    
    uint constant ERR_UNLOCK_NO_AVAILABLE_UTXOS = 60120;
    uint constant ERR_UNLOCK_UTXOS_VALUE_LESS_THAN_VALUE_TO_SEND = 60130;
    uint constant ERR_UNLOCK_VALUE_TO_SEND_LESS_THAN_FEE = 60140;



    // Variables sets by constructor
    // DogeRelay contract to trust. Only doge txs relayed from DogeRelay will be accepted.
    address public trustedDogeRelay;
    // Doge-Eth price oracle to trust.
    address public trustedDogeEthPriceOracle;
    // Number of times the operator eth collateral should cover her doge holdings 
    uint8 collateralRatio;


    // counter for next unlock
    uint32 public unlockIdx;
    // Unlocks the investor has not sent a proof of unlock yet.
    mapping (uint32 => Unlock) public unlocksPendingInvestorProof;
    // Doge-Eth currencies current market price.
    uint public dogeEthPrice;
    // operatorPublicKeyHash to Operator
    mapping (bytes20 => Operator) public operators;
    OperatorKey[] public operatorKeys;

    // Doge transactions that were already processed by processTransaction()
    Set.Data dogeTxHashesAlreadyProcessed;

    event ErrorDogeToken(uint err);
    event NewToken(address indexed user, uint value);
    event UnlockRequest(uint32 id, bytes20 operatorPublicKeyHash);

    // Represents an unlock request
    struct Unlock {
          address from;
          string dogeAddress;
          uint value;
          uint timestamp;
          // Values are indexes in storage array "utxos"
          uint32[] selectedUtxos;
          uint fee;
          bytes20 operatorPublicKeyHash;
    }

    struct Utxo {
          uint value;
          uint txHash;
          uint16 index;
    }

    struct Operator {
        address ethAddress;
        uint dogeAvailableBalance;
        uint dogePendingBalance;
        Utxo[] utxos;
        uint32 nextUnspentUtxoIndex;
        uint ethBalance;
        uint24 operatorKeyIndex;
    }

    struct OperatorKey { 
        bytes20 key; 
        bool deleted;
    }

    constructor (address _trustedDogeRelay, address _trustedDogeEthPriceOracle, uint8 _collateralRatio) public {
        trustedDogeRelay = _trustedDogeRelay;
        trustedDogeEthPriceOracle = _trustedDogeEthPriceOracle;
        collateralRatio = _collateralRatio;
    }

    // Adds an operator
    // @param operatorPublicKeyCompressed operator compressed public key (33 bytes). 
    //                          operatorPublicKeyCompressed[0] = odd (0x02 or 0x03)
    //                          operatorPublicKeyCompressed[1-32] = x
    // @param signature doubleSha256(msg.sender) signed by operator (65 bytes).
    //                  signature[0] = v
    //                  signature[1-32] = r
    //                  signature[33-64] = s
    function addOperator(bytes operatorPublicKeyCompressed, bytes signature) public {
        //log0(bytes32(operatorPublicKeyCompressed.length));
        //log0(bytes32(signature.length));

        // Parse operatorPublicKeyCompressed
        bytes32 operatorPublicKeyX;
        bool operatorPublicKeyOdd;
        operatorPublicKeyOdd = operatorPublicKeyCompressed[0] == 0x03;
        assembly {
            operatorPublicKeyX := mload(add(operatorPublicKeyCompressed, 0x21))
        }
        //log1(operatorPublicKeyX, bytes32(operatorPublicKeyOdd ? 1 : 0));

        // Check the non compressed version of operatorPublicKeyCompressed signed msg.sender hash
        bytes32 signedMessage = sha256(abi.encodePacked(sha256(abi.encodePacked(msg.sender))));
        //log1(bytes20(msg.sender), signedMessage);
        address recoveredAddress = ECRecovery.recover(signedMessage, signature);
        //log1(bytes32(recoveredAddress),
        //     bytes32(DogeTx.pub2address(uint(operatorPublicKeyX), operatorPublicKeyOdd)));                
        if (recoveredAddress != DogeTx.pub2address(uint(operatorPublicKeyX), operatorPublicKeyOdd)) {
            emit ErrorDogeToken(ERR_OPERATOR_SIGNATURE);
            return;
        }
        // Create operator
        bytes20 operatorPublicKeyHash = DogeTx.pub2PubKeyHash(operatorPublicKeyX, operatorPublicKeyOdd);
        //log0(operatorPublicKeyHash);
        Operator storage operator = operators[operatorPublicKeyHash];
        // Check operator does not exists yet
        //log1(bytes20(operator.ethAddress), bytes32((operator.ethAddress == 0) ? 0 : 1));
        if (operator.ethAddress != 0) {
            emit ErrorDogeToken(ERR_OPERATOR_ALREADY_CREATED);
            return;
        }        
        operator.ethAddress = msg.sender;
        operator.operatorKeyIndex = uint24(operatorKeys.length);
        operatorKeys.push(OperatorKey(operatorPublicKeyHash, false));
        
    }

    function deleteOperator(bytes20 operatorPublicKeyHash) public {
        Operator storage operator = operators[operatorPublicKeyHash];
        if (operator.ethAddress != msg.sender) {
            emit ErrorDogeToken(ERR_OPERATOR_NOT_CREATED_OR_WRONG_SENDER);
            return;
        }        
        if (operator.dogeAvailableBalance != 0 || operator.dogePendingBalance != 0 || operator.ethBalance != 0) {
            emit ErrorDogeToken(ERR_OPERATOR_HAS_BALANCE);
            return;
        }        

        OperatorKey storage operatorKey = operatorKeys[operator.operatorKeyIndex]; 
        operatorKey.deleted = true;
        delete operators[operatorPublicKeyHash];
    }

    function getOperatorsLength() public view returns (uint24) {
        return uint24(operatorKeys.length);
    }


    function addOperatorDeposit(bytes20 operatorPublicKeyHash) public payable {
        Operator storage operator = operators[operatorPublicKeyHash];
        if (operator.ethAddress != msg.sender) {
            emit ErrorDogeToken(ERR_OPERATOR_NOT_CREATED_OR_WRONG_SENDER);
            return;
        }        
        operator.ethBalance += msg.value;
    }

    function withdrawOperatorDeposit(bytes20 operatorPublicKeyHash, uint value) public {
        Operator storage operator = operators[operatorPublicKeyHash];
        if (operator.ethAddress != msg.sender) {
            emit ErrorDogeToken(ERR_OPERATOR_NOT_CREATED_OR_WRONG_SENDER);
            return;
        }
        if (operator.ethBalance < value) {
            emit ErrorDogeToken(ERR_OPERATOR_WITHDRAWAL_NOT_ENOUGH_BALANCE);
            return;
        }        
        if ((operator.ethBalance - value) / dogeEthPrice < (operator.dogeAvailableBalance + operator.dogePendingBalance) * collateralRatio) {
            emit ErrorDogeToken(ERR_OPERATOR_WITHDRAWAL_COLLATERAL_WOULD_BE_TOO_LOW);
            return;        
        }
        operator.ethBalance -= value;
        msg.sender.transfer(value);
    }


    function processTransaction(bytes dogeTx, uint txHash, bytes20 operatorPublicKeyHash) public returns (uint) {
        require(msg.sender == trustedDogeRelay);

        Operator storage operator = operators[operatorPublicKeyHash];
        // Check operator exists 
        if (operator.ethAddress == 0) {
            emit ErrorDogeToken(ERR_PROCESS_OPERATOR_NOT_CREATED);
            return;
        }        

        uint value;
        bytes32 firstInputPublicKeyX;
        bool firstInputPublicKeyOdd;
        uint16 outputIndex;
        (value, firstInputPublicKeyX, firstInputPublicKeyOdd, outputIndex) = DogeTx.parseTransaction(dogeTx, operatorPublicKeyHash);

        // Add tx to the dogeTxHashesAlreadyProcessed
        bool inserted = Set.insert(dogeTxHashesAlreadyProcessed, txHash);
        // Check tx was not already processed
        if (!inserted) {
            emit ErrorDogeToken(ERR_PROCESS_TX_ALREADY_PROCESSED);
            return;        
        }

        // Add utxo
        operator.utxos.push(Utxo(value, txHash, outputIndex));

        // Update operator's doge balance
        operator.dogeAvailableBalance += value;

        // See if the first input was signed by the operator
        bytes20 firstInputPublicKeyHash = DogeTx.pub2PubKeyHash(firstInputPublicKeyX, firstInputPublicKeyOdd);
        if (operatorPublicKeyHash != firstInputPublicKeyHash) {
            // this is a lock tx
            // Calculate ethereum address from dogecoin public key
            address destinationAddress = DogeTx.pub2address(uint(firstInputPublicKeyX), firstInputPublicKeyOdd);

            balances[destinationAddress] += value;
            emit NewToken(destinationAddress, value);
            // Hack to make etherscan show the event
            emit Transfer(0, destinationAddress, value);

            return value;
        } else {
            // this is an unlock tx
            // Update operator's doge balance
            operator.dogePendingBalance -= value;
            return 0;
        }
    }

    function wasDogeTxProcessed(uint txHash) public view returns (bool) {
        return Set.contains(dogeTxHashesAlreadyProcessed, txHash);
    }

    // Unlock section begin


    // Request ERC20 tokens to be burnt and dogecoins be received on the doge blockchain
    function doUnlock(string dogeAddress, uint value, bytes20 operatorPublicKeyHash) public returns (bool success) {
        if (value < MIN_UNLOCK_VALUE) {
            emit ErrorDogeToken(ERR_UNLOCK_MIN_UNLOCK_VALUE);
            return;
        }
        if (balances[msg.sender] < value) {
            emit ErrorDogeToken(ERR_UNLOCK_USER_BALANCE);
            return;
        }

        Operator storage operator = operators[operatorPublicKeyHash];
        // Check operator exists 
        if (operator.ethAddress == 0) {
            emit ErrorDogeToken(ERR_UNLOCK_OPERATOR_NOT_CREATED);
            return;
        }
        // Check operator available balance is enough
        if (operator.dogeAvailableBalance < value) {
            emit ErrorDogeToken(ERR_UNLOCK_OPERATOR_BALANCE);
            return;
        }

        uint32[] memory selectedUtxos;
        uint fee;
        uint changeValue;
        uint errorCode;
        (errorCode, selectedUtxos, fee, changeValue) = selectUtxosAndFee(value, operator);
        if (errorCode != 0) {
            emit ErrorDogeToken(errorCode);
            return;
        }

        balances[msg.sender] -= value;
        // Hack to make etherscan show the event
        emit Transfer(msg.sender, 0, value);
        emit UnlockRequest(unlockIdx, operatorPublicKeyHash);
        //log1(bytes32(selectedUtxos.length), bytes32(selectedUtxos[0]));
        unlocksPendingInvestorProof[unlockIdx] = Unlock(msg.sender, dogeAddress, value, 
                                                        block.timestamp, selectedUtxos, fee, operatorPublicKeyHash);
        // Update operator's doge balance
        operator.dogeAvailableBalance -= (value + changeValue);
        operator.dogePendingBalance += changeValue;
        operator.nextUnspentUtxoIndex += uint32(selectedUtxos.length);
        unlockIdx++;
        return true;
    }

    function selectUtxosAndFee(uint valueToSend, Operator operator) private pure returns (uint errorCode, uint32[] memory selectedUtxos, uint fee, uint changeValue) {
        // There should be at least 1 utxo available
        if (operator.nextUnspentUtxoIndex >= operator.utxos.length) {
            errorCode = ERR_UNLOCK_NO_AVAILABLE_UTXOS;
            return (errorCode, selectedUtxos, fee, changeValue);
        }
        fee = BASE_FEE;
        uint selectedUtxosValue;
        uint32 firstSelectedUtxo = operator.nextUnspentUtxoIndex;
        uint32 lastSelectedUtxo = firstSelectedUtxo;
        while (selectedUtxosValue < valueToSend && (lastSelectedUtxo < operator.utxos.length)) {
            selectedUtxosValue += operator.utxos[lastSelectedUtxo].value;
            fee += FEE_PER_INPUT;
            lastSelectedUtxo++;
        }
        if (selectedUtxosValue < valueToSend) {
            errorCode = ERR_UNLOCK_UTXOS_VALUE_LESS_THAN_VALUE_TO_SEND;
            return (errorCode, selectedUtxos, fee, changeValue);
        }
        if (valueToSend <= fee) {
            errorCode = ERR_UNLOCK_VALUE_TO_SEND_LESS_THAN_FEE;
            return (errorCode, selectedUtxos, fee, changeValue);
        }
        uint32 numberOfSelectedUtxos = lastSelectedUtxo - firstSelectedUtxo;
        selectedUtxos = new uint32[](numberOfSelectedUtxos);
        for(uint32 i = 0; i < numberOfSelectedUtxos; i++) {
            selectedUtxos[i] = i + firstSelectedUtxo;
        }
        changeValue = selectedUtxosValue - valueToSend;
        errorCode = 0;
        return (errorCode, selectedUtxos, fee, changeValue);
    }

    function setDogeEthPrice(uint _dogeEthPrice) public {
        require(msg.sender == trustedDogeEthPriceOracle);
        dogeEthPrice = _dogeEthPrice;
    }

    function getUnlockPendingInvestorProof(uint32 index) public view returns (address from, string dogeAddress, uint value, uint timestamp, uint32[] selectedUtxos, uint fee, bytes20 operatorPublicKeyHash) {
        Unlock storage unlock = unlocksPendingInvestorProof[index];
        from = unlock.from;
        dogeAddress = unlock.dogeAddress;
        value = unlock.value;
        timestamp = unlock.timestamp;
        selectedUtxos = unlock.selectedUtxos;
        fee = unlock.fee;
        operatorPublicKeyHash = unlock.operatorPublicKeyHash;
    }    

    function getUtxosLength(bytes20 operatorPublicKeyHash) public view returns (uint) {
        Operator storage operator = operators[operatorPublicKeyHash];
        return operator.utxos.length;
    }

    function getUtxo(bytes20 operatorPublicKeyHash, uint i) public view returns (uint value, uint txHash, uint16 index) {
        Operator storage operator = operators[operatorPublicKeyHash];
        Utxo storage utxo = operator.utxos[i];
        return (utxo.value, utxo.txHash, utxo.index);
    }

    // Unlock section end
}

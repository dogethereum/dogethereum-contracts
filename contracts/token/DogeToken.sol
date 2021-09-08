// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "./StandardToken.sol";
import "./Set.sol";
import "./../TransactionProcessor.sol";
import "../DogeParser/DogeMessageLibrary.sol";
import "./../ECRecovery.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol";

contract DogeToken is StandardToken, TransactionProcessor {

    using SafeMath for uint;

    // Lock constants
    uint public constant MIN_LOCK_VALUE = 300000000; // 3 doges
    uint public constant OPERATOR_LOCK_FEE = 10; // 1 = 0.1%
    uint public constant SUPERBLOCK_SUBMITTER_LOCK_FEE = 10; // 1 = 0.1%

    // Unlock constants
    uint public constant MIN_UNLOCK_VALUE = 300000000; // 3 doges
    uint public constant OPERATOR_UNLOCK_FEE = 10; // 1 = 0.1%
    uint constant DOGE_TX_BASE_FEE = 50000000; // 0.5 doge
    uint constant DOGE_TX_FEE_PER_INPUT = 100000000; // 1 doge

    // Used when calculating the operator and submitter fees for lock and unlock txs.
    uint public constant DOGETHEREUM_FEE_FRACTION = 1000;

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
    uint constant ERR_LOCK_MIN_LOCK_VALUE = 60180;

    // Token name
    string public constant name = "DogeToken";
    // Decimals for display purposes
    // How many decimals to show. ie. There could be 1000 base units with 3 decimals.
    // Meaning 0.980 SBX = 980 base units. It's like comparing 1 wei to 1 ether.
    uint8 public constant decimals = 8;
    // TODO: set an appropriate symbol
    string public constant symbol = "DOGETOKEN";

    // Contract to trust for tx included in a doge block verification.
    // Only doge txs relayed from trustedRelayerContract will be accepted.
    address public trustedRelayerContract;
    // Doge-Eth price oracle to trust.
    AggregatorV3Interface public dogeUsdOracle;
    AggregatorV3Interface public ethUsdOracle;
    // Number of times the eth collateral operator should cover her doge holdings
    uint8 public collateralRatio;


    // counter for next unlock
    uint32 public unlockIdx;
    // Unlocks for which the investor has not sent a proof of unlock yet.
    mapping (uint32 => Unlock) public unlocksPendingInvestorProof;
    // operatorPublicKeyHash to Operator
    mapping (bytes20 => Operator) public operators;
    OperatorKey[] public operatorKeys;

    // Doge transactions that were already processed by processTransaction()
    Set.Data dogeTxHashesAlreadyProcessed;

    event ErrorDogeToken(uint err);
    event NewToken(address indexed user, uint value);
    event UnlockRequest(uint32 id, bytes20 operatorPublicKeyHash);
    event OperatorCondemned(bytes20 operatorPublicKeyHash);

    // Represents an unlock request
    struct Unlock {
        address from;
        bytes20 dogeAddress;
        uint value;
        uint operatorFee;
        uint timestamp;
        // Values are indexes in storage array "utxos"
        uint32[] selectedUtxos;
        uint dogeTxFee;
        bytes20 operatorPublicKeyHash;
    }

    // TODO: value can fit in uint64 while index technically fits in uint64 too
    struct Utxo {
        // Value of the output.
        uint value;
        // Transaction hash.
        uint txHash;
        // Output index within the transaction.
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

    function initialize(
        address relayerContract,
        AggregatorV3Interface initDogeUsdOracle,
        AggregatorV3Interface initEthUsdOracle,
        uint8 initCollateralRatio
    ) external {
        require(trustedRelayerContract == address(0), "Contract already initialized!");
        require(relayerContract != address(0), "Relayer contract must be valid.");
        require(address(initDogeUsdOracle) != address(0), "Doge-Usd price oracle must be valid.");
        require(address(initEthUsdOracle) != address(0), "Eth-Usd price oracle must be valid.");

        trustedRelayerContract = relayerContract;
        dogeUsdOracle = initDogeUsdOracle;
        ethUsdOracle = initEthUsdOracle;
        collateralRatio = initCollateralRatio;
    }

    /**
     * Retrieves dogecoin price from oracle.
     *
     * @return dogePrice The price of a single dogecoin in ether weis.
     */
    function dogeEthPrice() public view returns (uint256 dogePrice) {
        (, int256 dogeUsdPrice,,,) = dogeUsdOracle.latestRoundData();
        (, int256 ethUsdPrice,,,) = ethUsdOracle.latestRoundData();
        return uint256(dogeUsdPrice).mul(1 ether).div(uint256(ethUsdPrice));
    }

    /**
     * Adds an operator
     * TODO: use fixed size parameters for the operator public key.
     * @param operatorPublicKeyCompressed operator compressed public key (33 bytes).
     *                          operatorPublicKeyCompressed[0] = odd (0x02 or 0x03)
     *                          operatorPublicKeyCompressed[1-32] = x
     * @param signature doubleSha256(msg.sender) signed by operator (65 bytes).
     *                  signature[0] = v
     *                  signature[1-32] = r
     *                  signature[33-64] = s
     */
    function addOperator(bytes memory operatorPublicKeyCompressed, bytes calldata signature) public {
        // Parse operatorPublicKeyCompressed
        bytes32 operatorPublicKeyX;
        bool operatorPublicKeyOdd;
        operatorPublicKeyOdd = operatorPublicKeyCompressed[0] == 0x03;
        assembly {
            operatorPublicKeyX := mload(add(operatorPublicKeyCompressed, 0x21))
        }

        // Check the non compressed version of operatorPublicKeyCompressed signed msg.sender hash
        bytes32 signedMessage = sha256(abi.encodePacked(sha256(abi.encodePacked(msg.sender))));
        address recoveredAddress = ECRecovery.recover(signedMessage, signature);
        if (recoveredAddress != DogeMessageLibrary.pub2address(uint(operatorPublicKeyX), operatorPublicKeyOdd)) {
            emit ErrorDogeToken(ERR_OPERATOR_SIGNATURE);
            return;
        }

        // Create operator
        bytes20 operatorPublicKeyHash = DogeMessageLibrary.pub2PubKeyHash(operatorPublicKeyX, operatorPublicKeyOdd);
        Operator storage operator = operators[operatorPublicKeyHash];

        // Check that operator does not exist yet
        if (operator.ethAddress != address(0)) {
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
        operator.ethBalance = operator.ethBalance.add(msg.value);
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
        uint256 ethPostWithdrawal = operator.ethBalance.sub(value);
        if (ethPostWithdrawal.div(dogeEthPrice()) <
            (operator.dogeAvailableBalance.add(operator.dogePendingBalance)).mul(collateralRatio)) {
            emit ErrorDogeToken(ERR_OPERATOR_WITHDRAWAL_COLLATERAL_WOULD_BE_TOO_LOW);
            return;
        }
        operator.ethBalance = ethPostWithdrawal;
        msg.sender.transfer(value);
    }

    function processLockTransaction(
        bytes calldata dogeTx,
        uint dogeTxHash,
        bytes20 operatorPublicKeyHash,
        address superblockSubmitterAddress
    ) override public {
        transactionPreliminaryChecks(dogeTxHash);
        Operator storage operator = getValidOperator(operatorPublicKeyHash);

        uint value;
        address lockDestinationEthAddress;
        uint16 outputIndex;
        (value, lockDestinationEthAddress, outputIndex) = DogeMessageLibrary.parseLockTransaction(dogeTx, operatorPublicKeyHash);

        // Add utxo
        if (value > 0) {
            operator.utxos.push(Utxo(value, dogeTxHash, outputIndex));
        }

        // Update operator's doge balance
        operator.dogeAvailableBalance = operator.dogeAvailableBalance.add(value);

        if (value < MIN_LOCK_VALUE) {
            emit ErrorDogeToken(ERR_LOCK_MIN_LOCK_VALUE);
            return;
        }

        distributeTokensAfterLock(lockDestinationEthAddress, value,
                               operator.ethAddress, superblockSubmitterAddress);
    }

    function processUnlockTransaction(
        bytes calldata dogeTx,
        uint dogeTxHash,
        bytes20 operatorPublicKeyHash,
        address /*superblockSubmitterAddress*/
    ) override public {
        transactionPreliminaryChecks(dogeTxHash);
        Operator storage operator = getValidOperator(operatorPublicKeyHash);

        uint userValue;
        uint operatorValue;
        uint16 outputIndex;
        (userValue, operatorValue, outputIndex) = DogeMessageLibrary.parseUnlockTransaction(dogeTx, operatorPublicKeyHash);

        // Add utxo
        if (operatorValue > 0) {
            operator.utxos.push(Utxo(operatorValue, dogeTxHash, outputIndex));

            // Update operator's doge balance
            operator.dogeAvailableBalance = operator.dogeAvailableBalance.add(operatorValue);
            operator.dogePendingBalance = operator.dogePendingBalance.sub(operatorValue);
        }
    }

    /**
     * Reports that an operator used an UTXO that wasn't yet requested for an unlock.
     */
    function processReportOperatorFreeUtxoSpend(
        bytes calldata dogeTx,
        uint dogeTxHash,
        bytes20 operatorPublicKeyHash,
        uint operatorTxOutputReference,
        uint32 unlawfulTxInputIndex
    ) external {
        transactionPreliminaryChecks(dogeTxHash);
        Operator storage operator = getValidOperator(operatorPublicKeyHash);

        require(operator.nextUnspentUtxoIndex <= operatorTxOutputReference, "The UTXO is already reserved or spent.");
        Utxo storage utxo = operator.utxos[operatorTxOutputReference];

        // Parse transaction and verify malfeasance claim
        (uint spentTxHash, uint32 spentTxIndex) = DogeMessageLibrary.getInputOutpoint(dogeTx, unlawfulTxInputIndex);
        require(
            spentTxHash == utxo.txHash && spentTxIndex == utxo.index,
            "The reported spent input and the UTXO are not the same."
        );

        // Condemn
        condemnOperator(operatorPublicKeyHash);
    }

    function transactionPreliminaryChecks(
        uint dogeTxHash
    ) internal {
        require(msg.sender == trustedRelayerContract, "Only the tx relayer can call this function.");

        // Add tx to the dogeTxHashesAlreadyProcessed
        bool inserted = Set.insert(dogeTxHashesAlreadyProcessed, dogeTxHash);
        // Check tx was not already processed
        require(inserted, "Transaction already processed.");
    }

    function getValidOperator(bytes20 operatorPublicKeyHash) internal view returns (Operator storage) {
        Operator storage operator = operators[operatorPublicKeyHash];
        require(operator.ethAddress != address(0), "Operator is not registered.");
        return operator;
    }

    function wasDogeTxProcessed(uint txHash) public view returns (bool) {
        return Set.contains(dogeTxHashesAlreadyProcessed, txHash);
    }

    function distributeTokensAfterLock(
        address destinationAddress,
        uint value,
        address operatorEthAddress,
        address superblockSubmitterAddress
    ) private {
        uint operatorFee = value.mul(OPERATOR_LOCK_FEE).div(DOGETHEREUM_FEE_FRACTION);
        mintTokens(operatorEthAddress, operatorFee);

        uint superblockSubmitterFee = value.mul(SUPERBLOCK_SUBMITTER_LOCK_FEE).div(DOGETHEREUM_FEE_FRACTION);
        mintTokens(superblockSubmitterAddress, superblockSubmitterFee);

        uint userValue = value.sub(operatorFee).sub(superblockSubmitterFee);
        mintTokens(destinationAddress, userValue);
    }

    function mintTokens(address destination, uint amount) private {
        balances[destination] = balances[destination].add(amount);
        emit NewToken(destination, amount);
        // Hack to make etherscan show the event
        emit Transfer(address(0), destination, amount);
    }


    // Unlock section begin

    // Request ERC20 tokens to be burnt and dogecoins be received on the doge blockchain
    function doUnlock(bytes20 dogeAddress, uint value, bytes20 operatorPublicKeyHash) public returns (bool success) {
        if (value < MIN_UNLOCK_VALUE) {
            emit ErrorDogeToken(ERR_UNLOCK_MIN_UNLOCK_VALUE);
            return false;
        }
        if (balances[msg.sender] < value) {
            emit ErrorDogeToken(ERR_UNLOCK_USER_BALANCE);
            return false;
        }

        Operator storage operator = operators[operatorPublicKeyHash];
        // Check that operator exists
        if (operator.ethAddress == address(0)) {
            emit ErrorDogeToken(ERR_UNLOCK_OPERATOR_NOT_CREATED);
            return false;
        }
        // Check that operator available balance is enough
        if (operator.dogeAvailableBalance < value) {
            emit ErrorDogeToken(ERR_UNLOCK_OPERATOR_BALANCE);
            return false;
        }

        uint operatorFee = value.mul(OPERATOR_UNLOCK_FEE).div(DOGETHEREUM_FEE_FRACTION);
        uint unlockValue = value.sub(operatorFee);

        uint32[] memory selectedUtxos;
        uint dogeTxFee;
        uint changeValue;
        uint errorCode;
        (errorCode, selectedUtxos, dogeTxFee, changeValue) = selectUtxosAndFee(unlockValue, operator);
        if (errorCode != 0) {
            emit ErrorDogeToken(errorCode);
            return false;
        }

        balances[operator.ethAddress] = balances[operator.ethAddress].add(operatorFee);
        emit Transfer(msg.sender, operator.ethAddress, operatorFee);
        balances[msg.sender] = balances[msg.sender].sub(value);
        // Hack to make etherscan show the event
        emit Transfer(msg.sender, address(0), unlockValue);

        emit UnlockRequest(unlockIdx, operatorPublicKeyHash);
        unlocksPendingInvestorProof[unlockIdx] = Unlock(msg.sender, dogeAddress, value,
                                                        operatorFee,
                                                        block.timestamp, selectedUtxos, dogeTxFee,
                                                        operatorPublicKeyHash);
        // Update operator's doge balance
        operator.dogeAvailableBalance = operator.dogeAvailableBalance.sub(unlockValue.add(changeValue));
        operator.dogePendingBalance = operator.dogePendingBalance.add(changeValue);
        operator.nextUnspentUtxoIndex += uint32(selectedUtxos.length);
        unlockIdx++;
        return true;
    }

    function selectUtxosAndFee(uint valueToSend, Operator memory operator) private pure returns (uint errorCode, uint32[] memory selectedUtxos, uint dogeTxFee, uint changeValue) {
        // There should be at least 1 utxo available
        if (operator.nextUnspentUtxoIndex >= operator.utxos.length) {
            errorCode = ERR_UNLOCK_NO_AVAILABLE_UTXOS;
            return (errorCode, selectedUtxos, dogeTxFee, changeValue);
        }
        dogeTxFee = DOGE_TX_BASE_FEE;
        uint selectedUtxosValue;
        uint32 firstSelectedUtxo = operator.nextUnspentUtxoIndex;
        uint32 lastSelectedUtxo = firstSelectedUtxo;
        while (selectedUtxosValue < valueToSend && (lastSelectedUtxo < operator.utxos.length)) {
            selectedUtxosValue = selectedUtxosValue.add(operator.utxos[lastSelectedUtxo].value);
            dogeTxFee = dogeTxFee.add(DOGE_TX_FEE_PER_INPUT);
            lastSelectedUtxo++;
        }
        if (selectedUtxosValue < valueToSend) {
            errorCode = ERR_UNLOCK_UTXOS_VALUE_LESS_THAN_VALUE_TO_SEND;
            return (errorCode, selectedUtxos, dogeTxFee, changeValue);
        }
        if (valueToSend <= dogeTxFee) {
            errorCode = ERR_UNLOCK_VALUE_TO_SEND_LESS_THAN_FEE;
            return (errorCode, selectedUtxos, dogeTxFee, changeValue);
        }
        uint32 numberOfSelectedUtxos = lastSelectedUtxo - firstSelectedUtxo;
        selectedUtxos = new uint32[](numberOfSelectedUtxos);
        for(uint32 i = 0; i < numberOfSelectedUtxos; i++) {
            selectedUtxos[i] = i + firstSelectedUtxo;
        }
        changeValue = selectedUtxosValue.sub(valueToSend);
        errorCode = 0;
        return (errorCode, selectedUtxos, dogeTxFee, changeValue);
    }

    function condemnOperator(bytes20 operatorPublicKeyHash) internal {
        // TODO: implement
        emit OperatorCondemned(operatorPublicKeyHash);
    }

    function getUnlockPendingInvestorProof(uint32 index) public view returns (address from, bytes20 dogeAddress, uint value, uint operatorFee, uint timestamp, uint32[] memory selectedUtxos, uint dogeTxFee, bytes20 operatorPublicKeyHash) {
        Unlock storage unlock = unlocksPendingInvestorProof[index];
        from = unlock.from;
        dogeAddress = unlock.dogeAddress;
        value = unlock.value;
        operatorFee = unlock.operatorFee;
        timestamp = unlock.timestamp;
        selectedUtxos = unlock.selectedUtxos;
        dogeTxFee = unlock.dogeTxFee;
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

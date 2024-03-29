// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol";

import "../TransactionProcessor.sol";
import "../DogeParser/DogeMessageLibrary.sol";
import "../ECRecovery.sol";
import "../DogeSuperblocks.sol";

import "./StandardToken.sol";
import "./Set.sol";
import "./EtherAuction.sol";

contract DogeToken is StandardToken, TransactionProcessor, EtherAuction {
  using SafeMath for uint256;

  /** Dogecoin and bridge fee constants **/

  // Care must be taken when modifying these constants.
  // In particular, there is a delicate balance between the dogecoin dust limit,
  // the operator fee and the minimum unlock value.
  // These should be set so that for all unlock transactions that have a change value
  // under the dust limit, the change amount can be taken out of the operator fees.
  // Concisely, if the operator change is dust, the following equation must hold:
  // dust < MIN_UNLOCK_VALUE * OPERATOR_UNLOCK_FEE / DOGETHEREUM_FEE_FRACTION
  // This ensures that the amount of circulating DogeTokens coincides with
  // the amount of dogecoins locked with operators.

  // Lock constants
  uint256 public constant MIN_LOCK_VALUE = 300000000; // 3 doges
  uint256 public constant OPERATOR_LOCK_FEE = 10;
  uint256 public constant SUPERBLOCK_SUBMITTER_LOCK_FEE = 10;

  // Unlock constants
  uint256 public constant MIN_UNLOCK_VALUE = 300000000; // 3 doges
  uint256 public constant OPERATOR_UNLOCK_FEE = 10;

  // Tx fee rate is the amount of satoshis per byte paid to the miner in a given transaction.
  // 0.01 doge/kB = 0.00001 doge/B
  uint256 public constant DOGE_TX_FEE_RATE = 1000;
  // Soft dust limit. Values under this limit are considered dust and must pay additional fees.
  // See https://github.com/dogecoin/dogecoin/blob/master/doc/fee-recommendation.md
  uint256 public constant DOGE_DUST = 1000000;
  // Tx input with P2PKH redeem script size in bytes
  uint256 public constant DOGE_TX_INPUT_SIZE = 148;
  // Tx output with P2PKH lock script size in bytes
  uint256 public constant DOGE_TX_OUTPUT_SIZE = 34;
  // This is the size in bytes of the constant sized parts of a Dogecoin tx.
  // We assume that var ints for amounts of inputs and outputs are at most 1 byte long.
  // This implies that there are both less than 0xfd = 253 inputs and 253 outputs.
  // s(version) + s(n_tx_in) + s(n_tx_out) + s(lock_time)
  uint256 public constant DOGE_TX_FIXED_SIZE = 4 + 1 + 1 + 4;

  // Used when calculating the operator and submitter fees for lock and unlock txs.
  // 1 fee point = 0.1% of tx value
  uint256 public constant DOGETHEREUM_FEE_FRACTION = 1000;

  /** End of economics sensitive constants **/

  // Note: ideally, these state variables would be Solidity immutables but the upgrades plugin
  // doesn't play nice with Solidity immutables in logic contracts yet.
  // Ethereum time lapse in which the operator can complete an unlock without repercussions.
  uint256 public ethereumTimeGracePeriod;
  // Amount of superblocks that need to be confirmed before an unlock can be reported as missing.
  uint256 public superblocksHeightGracePeriod;

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
  // Contract that stores the superblockchain.
  // Note that in production the superblockchain contract should be the same as the relayer contract.
  // We separate these roles to write some tests more easily
  DogeSuperblocks public superblocks;

  // Note: ideally, these state variables would be Solidity immutables but the upgrades plugin
  // doesn't play nice with Solidity immutables in logic contracts yet.
  // Doge-Eth price oracle to trust.
  AggregatorV3Interface public dogeUsdOracle;
  AggregatorV3Interface public ethUsdOracle;
  // Number of times the eth collateral operator should cover her doge holdings
  // An operator is not allowed to withdraw collateral if the resulting ratio is lower than this.
  // Additionally, lock implementors should avoid requesting locks that would result in an operator
  // falling below this ratio.
  uint256 public lockCollateralRatio;
  // Liquidation threshold for the eth collateral of an operator.
  // If an operator has a collateral ratio below this threshold, her collateral is liable to liquidation.
  // This ratio is expressed in thousandths of the ether to dogecoin ratio.
  // For example, if the ether to dogecoin ratio is 1.5, this would be stored as 1.5 * 1000 = 1500
  uint256 public liquidationThreshold;
  // Used when interpreting collateral ratios like lockCollateralRatio and liquidationThreshold.
  uint256 public constant DOGETHEREUM_COLLATERAL_RATIO_FRACTION = 1000;

  // counter for next unlock
  uint256 public unlockIdx;
  // Unlocks for which the investor has not sent a proof of unlock yet.
  mapping(uint256 => Unlock) public unlocks;
  // operatorPublicKeyHash to Operator
  mapping(bytes20 => Operator) public operators;
  OperatorKey[] public operatorKeys;

  // Doge transactions that were already processed by processTransaction()
  Set.Data dogeTxHashesAlreadyProcessed;

  event NewToken(address indexed user, uint256 value);
  event UnlockRequest(uint256 id, bytes20 operatorPublicKeyHash);
  // Indicates that a collateral auction was started for the operator.
  // The auction can be closed if the block timestamp is higher than `endTimestamp`.
  event OperatorLiquidated(bytes20 operatorPublicKeyHash, uint256 endTimestamp);
  // Collateral auction bid
  event LiquidationBid(bytes20 operatorPublicKeyHash, address bidder, uint256 bid);
  // End of the collateral auction.
  event OperatorCollateralAuctioned(
    bytes20 operatorPublicKeyHash,
    address winner,
    uint256 tokensBurned,
    uint256 etherSold
  );
  /**
   * @param user Ethereum Operator address
   * @param value Dogecoins being locked
   * @param operatorFee Dogecoins paid to Operator
   * @param superblockSubmitterFee Dogecoins paid to Submitter
   */
  event LockedToken(
    address indexed user,
    uint256 value,
    uint256 operatorFee,
    uint256 superblockSubmitterFee
  );
  /**
   * @param user Ethereum Operator address
   * @param value Dogecoins being unlocked
   * @param operatorFee Dogecoins paid to the Operator
   * @param dogeTxFee Dogecoins paid to Dogecoin Miner
   */
  event UnlockedToken(address indexed user, uint256 value, uint256 operatorFee, uint256 dogeTxFee);

  // Represents an unlock request
  struct Unlock {
    address from;
    bytes20 dogeAddress;
    // TODO: value to user can fit in uint64
    uint256 valueToUser;
    // TODO: change can fit in uint64
    uint256 operatorChange;
    // Block timestamp at which this request was made.
    uint256 timestamp;
    // Superblock height at which this request was made.
    uint256 superblockHeight;
    // List of indexes of the corresponding utxos in the Operator struct
    uint32[] selectedUtxos;
    // Operator public key hash. Key for the operators mapping.
    bytes20 operatorPublicKeyHash;
    // This marks the unlock as complete or incomplete.
    // An unlock is complete if the unlock transaction was relayed to the bridge.
    bool completed;
  }

  struct Utxo {
    // TODO: value can fit in uint64
    // Value of the output.
    uint256 value;
    // Transaction hash.
    uint256 txHash;
    // Output index within the transaction.
    uint32 index;
  }

  struct Operator {
    address ethAddress;
    uint256 dogeAvailableBalance;
    uint256 dogePendingBalance;
    Utxo[] utxos;
    uint32 nextUnspentUtxoIndex;
    uint256 ethBalance;
    uint24 operatorKeyIndex;
    Auction auction;
  }

  struct OperatorKey {
    bytes20 key;
    bool deleted;
  }

  function initialize(
    address relayerContract,
    DogeSuperblocks initSuperblocks,
    AggregatorV3Interface initDogeUsdOracle,
    AggregatorV3Interface initEthUsdOracle,
    uint256 initLockCollateralRatio,
    uint256 initLiquidationThreshold,
    uint256 timeGracePeriod,
    uint256 superblocksGracePeriod
  ) external {
    require(trustedRelayerContract == address(0), "Contract already initialized!");

    require(relayerContract != address(0), "Relayer contract must be valid.");
    require(address(initSuperblocks) != address(0), "Superblockchain contract must be valid.");
    require(address(initDogeUsdOracle) != address(0), "Doge-Usd price oracle must be valid.");
    require(address(initEthUsdOracle) != address(0), "Eth-Usd price oracle must be valid.");
    require(
      initLockCollateralRatio > initLiquidationThreshold,
      "The lock and withdrawal threshold ratio should be greater than the liquidation threshold."
    );
    require(
      initLiquidationThreshold > DOGETHEREUM_COLLATERAL_RATIO_FRACTION,
      "The liquidation threshold ratio should be greater than 1."
    );
    require(timeGracePeriod > 0, "Time grace period should be greater than 0.");
    require(superblocksGracePeriod > 0, "Superblocks grace period should be greater than 0.");

    trustedRelayerContract = relayerContract;
    superblocks = initSuperblocks;
    dogeUsdOracle = initDogeUsdOracle;
    ethUsdOracle = initEthUsdOracle;
    liquidationThreshold = initLiquidationThreshold;
    lockCollateralRatio = initLockCollateralRatio;
    ethereumTimeGracePeriod = timeGracePeriod;
    superblocksHeightGracePeriod = superblocksGracePeriod;
  }

  /**
   * Retrieves dogecoin price from oracle.
   *
   * @return dogePrice The price of a single dogecoin in ether weis.
   */
  function dogeEthPrice() public view returns (uint256 dogePrice) {
    (, int256 dogeUsdPrice, , , ) = dogeUsdOracle.latestRoundData();
    (, int256 ethUsdPrice, , , ) = ethUsdOracle.latestRoundData();
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
    require(
      recoveredAddress ==
        DogeMessageLibrary.pub2address(uint256(operatorPublicKeyX), operatorPublicKeyOdd),
      "Bad operator signature."
    );

    // Create operator
    bytes20 operatorPublicKeyHash = DogeMessageLibrary.pub2PubKeyHash(
      operatorPublicKeyX,
      operatorPublicKeyOdd
    );
    Operator storage operator = operators[operatorPublicKeyHash];

    // Check that operator does not exist yet
    require(operator.ethAddress == address(0), "Operator already created.");
    operator.ethAddress = msg.sender;
    operator.operatorKeyIndex = uint24(operatorKeys.length);
    operatorKeys.push(OperatorKey(operatorPublicKeyHash, false));
  }

  function deleteOperator(bytes20 operatorPublicKeyHash) public {
    Operator storage operator = operators[operatorPublicKeyHash];
    // Error: The operator doesn't exist or the sender is not authorized to delete this operator.
    require(operator.ethAddress == msg.sender, "ERR_DELETE_OPERATOR_NOT_CREATED_OR_WRONG_SENDER");
    // Error: The operator has some dogecoin or ether balance.
    require(
      operator.dogeAvailableBalance == 0 &&
        operator.dogePendingBalance == 0 &&
        operator.ethBalance == 0,
      "ERR_DELETE_OPERATOR_HAS_BALANCE"
    );

    OperatorKey storage operatorKey = operatorKeys[operator.operatorKeyIndex];
    operatorKey.deleted = true;
    delete operators[operatorPublicKeyHash];
  }

  function getOperatorsLength() public view returns (uint24) {
    return uint24(operatorKeys.length);
  }

  function addOperatorDeposit(bytes20 operatorPublicKeyHash) public payable {
    Operator storage operator = operators[operatorPublicKeyHash];
    // Error: The operator doesn't exist or the sender is not authorized to add deposit for this operator.
    require(
      operator.ethAddress == msg.sender,
      "ERR_ADD_DEPOSIT_OPERATOR_NOT_CREATED_OR_WRONG_SENDER"
    );
    operator.ethBalance = operator.ethBalance.add(msg.value);
  }

  function withdrawOperatorDeposit(bytes20 operatorPublicKeyHash, uint256 value) public {
    Operator storage operator = operators[operatorPublicKeyHash];
    // Error: The operator doesn't exist or the sender is not authorized to withdraw deposit for this operator.
    require(
      operator.ethAddress == msg.sender,
      "ERR_WITHDRAW_DEPOSIT_OPERATOR_NOT_CREATED_OR_WRONG_SENDER"
    );

    // Error: The operator doesn't have enough balance.
    require(operator.ethBalance >= value, "ERR_WITHDRAW_DEPOSIT_NOT_ENOUGH_BALANCE");
    uint256 ethPostWithdrawal = operator.ethBalance.sub(value);
    // Error: The resulting collateral of the operator would be too low.
    require(
      ethPostWithdrawal.mul(DOGETHEREUM_COLLATERAL_RATIO_FRACTION).div(dogeEthPrice()) >=
        (operator.dogeAvailableBalance.add(operator.dogePendingBalance)).mul(lockCollateralRatio),
      "ERR_WITHDRAW_DEPOSIT_COLLATERAL_WOULD_BE_TOO_LOW"
    );
    operator.ethBalance = ethPostWithdrawal;
    msg.sender.transfer(value);
  }

  function processLockTransaction(
    bytes calldata dogeTx,
    uint256 dogeTxHash,
    bytes20 operatorPublicKeyHash,
    address superblockSubmitterAddress
  ) public override {
    transactionPreliminaryChecks(dogeTxHash);
    Operator storage operator = getActiveOperator(operatorPublicKeyHash);

    uint256 value;
    address lockDestinationEthAddress;
    uint32 outputIndex;
    (value, lockDestinationEthAddress, outputIndex) = DogeMessageLibrary.parseLockTransaction(
      dogeTx,
      operatorPublicKeyHash
    );

    require(value >= MIN_LOCK_VALUE, "Lock value is too low.");

    // Add utxo
    operator.utxos.push(Utxo({value: value, txHash: dogeTxHash, index: outputIndex}));

    // Update operator's doge balance
    operator.dogeAvailableBalance = operator.dogeAvailableBalance.add(value);

    distributeTokensAfterLock(
      lockDestinationEthAddress,
      value,
      operator.ethAddress,
      superblockSubmitterAddress
    );
  }

  function processUnlockTransaction(
    bytes calldata dogeTx,
    uint256 dogeTxHash,
    bytes20 operatorPublicKeyHash,
    uint256 unlockIndex
  ) public override {
    transactionPreliminaryChecks(dogeTxHash);
    Operator storage operator = getActiveOperator(operatorPublicKeyHash);
    Unlock storage unlock = getValidUnlock(unlockIndex);

    // Expected number of outputs for this unlock
    // We only want one or two outputs. We ignore the rest of the outputs.
    // If there's no change for the operator, we only check the output for the user.
    uint256 numberOfOutputs = unlock.operatorChange > 0 ? 2 : 1;

    DogeMessageLibrary.Outpoint[] memory outpoints;
    DogeMessageLibrary.P2PKHOutput[] memory outputs;
    (outpoints, outputs) = DogeMessageLibrary.parseUnlockTransaction(
      dogeTx,
      unlock.selectedUtxos.length,
      numberOfOutputs
    );

    // Ensure utxos reserved for the unlock were spent.
    for (uint256 i = 0; i < unlock.selectedUtxos.length; i++) {
      uint32 utxoIndex = unlock.selectedUtxos[i];
      Utxo storage utxo = operator.utxos[utxoIndex];
      require(utxo.txHash == outpoints[i].txHash, "Unexpected tx hash reference in input.");
      require(utxo.index == outpoints[i].txIndex, "Unexpected tx output index reference in input.");
    }

    require(
      outputs[0].publicKeyHash == unlock.dogeAddress,
      "Wrong dogecoin public key hash for user."
    );
    require(outputs[0].value == unlock.valueToUser, "Wrong amount of dogecoins sent to user.");

    // If the unlock transaction has operator change
    if (numberOfOutputs > 1) {
      uint32 operatorOutputIndex = 1;
      uint256 operatorValue = outputs[operatorOutputIndex].value;
      require(
        outputs[operatorOutputIndex].publicKeyHash == unlock.operatorPublicKeyHash,
        "Wrong dogecoin public key hash for operator."
      );
      require(operatorValue == unlock.operatorChange, "Wrong change amount for the operator.");

      // Add utxo
      operator.utxos.push(Utxo(operatorValue, dogeTxHash, operatorOutputIndex));

      // Update operator's doge balance
      operator.dogeAvailableBalance = operator.dogeAvailableBalance.add(operatorValue);
      operator.dogePendingBalance = operator.dogePendingBalance.sub(operatorValue);
    }

    // Mark the unlock as completed.
    unlock.completed = true;
  }

  /**
   * Reports that an operator used an UTXO that wasn't yet requested for an unlock.
   */
  function processReportOperatorFreeUtxoSpend(
    bytes calldata dogeTx,
    uint256 dogeTxHash,
    bytes20 operatorPublicKeyHash,
    uint32 operatorTxOutputReference,
    uint32 unlawfulTxInputIndex
  ) public override {
    transactionPreliminaryChecks(dogeTxHash);
    Operator storage operator = getActiveOperator(operatorPublicKeyHash);

    require(
      operator.nextUnspentUtxoIndex <= operatorTxOutputReference,
      "The UTXO is already reserved or spent."
    );
    Utxo storage utxo = operator.utxos[operatorTxOutputReference];

    // Parse transaction and verify malfeasance claim
    (uint256 spentTxHash, uint32 spentTxIndex) = DogeMessageLibrary.getInputOutpoint(
      dogeTx,
      unlawfulTxInputIndex
    );
    require(
      spentTxHash == utxo.txHash && spentTxIndex == utxo.index,
      "The reported spent input and the UTXO are not the same."
    );

    liquidateOperator(operatorPublicKeyHash, operator);
  }

  /**
   * Reports that an operator did not complete the unlock request in time.
   */
  function reportOperatorMissingUnlock(bytes20 operatorPublicKeyHash, uint256 unlockIndex)
    external
  {
    Operator storage operator = getActiveOperator(operatorPublicKeyHash);

    Unlock storage unlock = getValidUnlock(unlockIndex);

    require(
      block.timestamp > uint256(unlock.timestamp).add(ethereumTimeGracePeriod),
      "The unlock is still within the time grace period."
    );

    uint256 superblockchainHeight = superblocks.getChainHeight();
    require(
      superblockchainHeight > unlock.superblockHeight.add(superblocksHeightGracePeriod),
      "The unlock is still within the superblockchain height grace period."
    );

    liquidateOperator(operatorPublicKeyHash, operator);
  }

  /**
   * Reports that an operator does not have enough collateral.
   */
  function reportOperatorUnsafeCollateral(bytes20 operatorPublicKeyHash) external {
    Operator storage operator = getActiveOperator(operatorPublicKeyHash);

    uint256 totalDogeBalance = operator.dogeAvailableBalance.add(operator.dogePendingBalance).mul(
      DOGETHEREUM_COLLATERAL_RATIO_FRACTION
    );
    uint256 collateralValue = operator.ethBalance.mul(liquidationThreshold).div(dogeEthPrice());
    require(
      collateralValue < totalDogeBalance,
      "The operator has enough collateral to be considered safe."
    );

    liquidateOperator(operatorPublicKeyHash, operator);
  }

  function transactionPreliminaryChecks(uint256 dogeTxHash) internal {
    require(msg.sender == trustedRelayerContract, "Only the tx relayer can call this function.");

    // Add tx to the dogeTxHashesAlreadyProcessed
    bool inserted = Set.insert(dogeTxHashesAlreadyProcessed, dogeTxHash);
    // Check tx was not already processed
    require(inserted, "Transaction already processed.");
  }

  function getValidOperator(bytes20 operatorPublicKeyHash)
    internal
    view
    returns (Operator storage)
  {
    Operator storage operator = operators[operatorPublicKeyHash];
    require(operator.ethAddress != address(0), "Operator is not registered.");
    return operator;
  }

  function getActiveOperator(bytes20 operatorPublicKeyHash)
    internal
    view
    returns (Operator storage)
  {
    Operator storage operator = getValidOperator(operatorPublicKeyHash);
    require(auctionIsInexistent(operator.auction), "Operator is liquidated.");
    return operator;
  }

  function wasDogeTxProcessed(uint256 txHash) public view returns (bool) {
    return Set.contains(dogeTxHashesAlreadyProcessed, txHash);
  }

  function distributeTokensAfterLock(
    address destinationAddress,
    uint256 value,
    address operatorEthAddress,
    address superblockSubmitterAddress
  ) private {
    // TODO: optimize gas costs when superblock submitter and operator are the same address?
    uint256 operatorFee = value.mul(OPERATOR_LOCK_FEE).div(DOGETHEREUM_FEE_FRACTION);
    mintTokens(operatorEthAddress, operatorFee);

    uint256 superblockSubmitterFee = value.mul(SUPERBLOCK_SUBMITTER_LOCK_FEE).div(
      DOGETHEREUM_FEE_FRACTION
    );
    mintTokens(superblockSubmitterAddress, superblockSubmitterFee);

    uint256 userValue = value.sub(operatorFee).sub(superblockSubmitterFee);
    mintTokens(destinationAddress, userValue);

    // Update the total supply with the sum of the three minted amounts.
    totalSupply = totalSupply.add(value);

    emit LockedToken({
      user: operatorEthAddress,
      value: value,
      operatorFee: operatorFee,
      superblockSubmitterFee: superblockSubmitterFee
    });
  }

  /**
   * @dev Note that this doesn't update the total supply.
   * The total supply must be updated accordingly by the caller.
   */
  function mintTokens(address destination, uint256 amount) private {
    balances[destination] = balances[destination].add(amount);

    emit NewToken(destination, amount);
    // Hack to make etherscan show the event
    emit Transfer(address(0), destination, amount);
  }

  function liquidateOperator(bytes20 operatorPublicKeyHash, Operator storage operator) internal {
    uint256 endTimestamp = auctionOpen(operator.auction);
    emit OperatorLiquidated(operatorPublicKeyHash, endTimestamp);
  }

  /*  Auction section  */

  /**
   * Bid in the collateral auction of a liquidated operator.
   * The sender must have enough tokens for the bid.
   */
  function liquidationBid(bytes20 operatorPublicKeyHash, uint256 tokenAmount) external {
    Operator storage operator = getValidOperator(operatorPublicKeyHash);

    auctionBid(operator.auction, msg.sender, tokenAmount);

    emit LiquidationBid(operatorPublicKeyHash, msg.sender, tokenAmount);
  }

  /**
   * @dev Used in the Auction bidding logic.
   * Total supply is updated once the auction is closed.
   */
  function takeTokens(address bidder, uint256 tokenAmount) internal override {
    require(balances[bidder] >= tokenAmount, "Not enough tokens for bid.");
    balances[bidder] = balances[bidder].sub(tokenAmount);
  }

  /**
   * @dev Used in the Auction bidding logic.
   * Total supply is updated once the auction is closed.
   */
  function releaseTokens(address bidder, uint256 tokenAmount) internal override {
    balances[bidder] = balances[bidder].add(tokenAmount);
  }

  /**
   * Close the auction.
   * This triggers a payment to the winner.
   * The winning account needs to be able to receive an ether transfer with 2300 gas.
   */
  function closeLiquidationAuction(bytes20 operatorPublicKeyHash) external {
    Operator storage operator = getValidOperator(operatorPublicKeyHash);

    address payable winner;
    uint256 winningBid;
    // We don't need to update token balances since we already guarantee
    // that the tokens are unavailable at this point.
    (winner, winningBid) = auctionClose(operator.auction);

    uint256 collateral = operator.ethBalance;
    operator.ethBalance = 0;
    // Here we burn the tokens in the bid.
    totalSupply = totalSupply.sub(winningBid);

    winner.transfer(collateral);

    // Doge tokens burn event
    // Hack to make etherscan show the event
    emit Transfer(winner, address(0), winningBid);

    emit OperatorCollateralAuctioned(operatorPublicKeyHash, winner, winningBid, collateral);
  }

  /*  End of auction section  */

  // Unlock section begin

  // Request ERC20 tokens to be burnt and dogecoins be received on the doge blockchain
  function doUnlock(
    bytes20 dogeAddress,
    uint256 value,
    bytes20 operatorPublicKeyHash
  ) public {
    require(value >= MIN_UNLOCK_VALUE, "Can't unlock small amounts.");
    require(balances[msg.sender] >= value, "User doesn't have enough token balance.");

    Operator storage operator = getActiveOperator(operatorPublicKeyHash);

    // Check that operator available balance is enough
    uint256 operatorFee = value.mul(OPERATOR_UNLOCK_FEE).div(DOGETHEREUM_FEE_FRACTION);
    uint256 unlockValue = value.sub(operatorFee);
    require(operator.dogeAvailableBalance >= unlockValue, "Operator doesn't have enough balance.");

    (
      uint32[] memory selectedUtxos,
      uint256 dogeTxFee,
      uint256 changeValue,
      uint256 dust
    ) = selectUtxosAndFee(unlockValue, operator);
    // If the resulting change is dust, it's taken out of the operator fee to maintain
    // the ratio between DogeTokens and dogecoins locked by operators.
    // Note that the dust should always be less than the operator fee.
    operatorFee = operatorFee.sub(dust);

    balances[msg.sender] = balances[msg.sender].sub(value);

    balances[operator.ethAddress] = balances[operator.ethAddress].add(operatorFee);
    emit Transfer(msg.sender, operator.ethAddress, operatorFee);

    uint256 burnt = unlockValue.add(dust);
    totalSupply = totalSupply.sub(burnt);
    // Hack to make etherscan show the event
    emit Transfer(msg.sender, address(0), burnt);

    // Get superblockchain height
    uint256 superblockchainHeight = superblocks.getChainHeight();

    emit UnlockRequest(unlockIdx, operatorPublicKeyHash);
    // The value sent to the user is the unlock value minus the doge tx fee.
    unlocks[unlockIdx] = Unlock(
      msg.sender,
      dogeAddress,
      unlockValue.sub(dogeTxFee),
      changeValue,
      block.timestamp,
      superblockchainHeight,
      selectedUtxos,
      operatorPublicKeyHash,
      false
    );
    // Update operator's doge balance
    operator.dogeAvailableBalance = operator
      .dogeAvailableBalance
      .sub(unlockValue.add(changeValue))
      .sub(dust);
    operator.dogePendingBalance = operator.dogePendingBalance.add(changeValue);
    operator.nextUnspentUtxoIndex += uint32(selectedUtxos.length);
    unlockIdx++;

    emit UnlockedToken({
      user: operator.ethAddress,
      value: value,
      operatorFee: operatorFee,
      dogeTxFee: dogeTxFee
    });
  }

  function selectUtxosAndFee(uint256 valueToSend, Operator memory operator)
    private
    pure
    returns (
      uint32[] memory selectedUtxos,
      uint256 dogeTxFee,
      uint256 changeValue,
      uint256 dust
    )
  {
    // There should be at least 1 utxo available
    require(
      operator.nextUnspentUtxoIndex < operator.utxos.length,
      "No available UTXOs for this operator."
    );

    uint256 selectedUtxosValue;
    uint32 firstSelectedUtxo = operator.nextUnspentUtxoIndex;
    uint32 lastSelectedUtxo = firstSelectedUtxo;
    while (selectedUtxosValue < valueToSend && (lastSelectedUtxo < operator.utxos.length)) {
      selectedUtxosValue = selectedUtxosValue.add(operator.utxos[lastSelectedUtxo].value);
      lastSelectedUtxo++;
    }
    require(
      selectedUtxosValue >= valueToSend,
      "Available UTXOs don't cover requested unlock amount."
    );

    uint32 numberOfSelectedUtxos = lastSelectedUtxo - firstSelectedUtxo;
    selectedUtxos = new uint32[](numberOfSelectedUtxos);
    for (uint32 i = 0; i < numberOfSelectedUtxos; i++) {
      selectedUtxos[i] = i + firstSelectedUtxo;
    }

    uint256 dogeTxSize = DOGE_TX_FIXED_SIZE;
    dogeTxSize = dogeTxSize.add(DOGE_TX_INPUT_SIZE.mul(numberOfSelectedUtxos));

    changeValue = selectedUtxosValue.sub(valueToSend);
    dust = 0;

    if (changeValue < DOGE_DUST) {
      dust = changeValue;
      changeValue = 0;
    }

    if (changeValue > 0) {
      dogeTxSize = dogeTxSize.add(DOGE_TX_OUTPUT_SIZE.mul(2));
    } else {
      dogeTxSize = dogeTxSize.add(DOGE_TX_OUTPUT_SIZE);
    }

    dogeTxFee = dust.add(DOGE_TX_FEE_RATE.mul(dogeTxSize));

    require(valueToSend > dogeTxFee, "Requested unlock amount can't cover tx fees.");
    return (selectedUtxos, dogeTxFee, changeValue, dust);
  }

  function getValidUnlock(uint256 index) internal view returns (Unlock storage) {
    require(index < unlockIdx, "The unlock request doesn't exist.");
    return unlocks[index];
  }

  function getUnlock(uint256 index)
    public
    view
    returns (
      address from,
      bytes20 dogeAddress,
      uint256 valueToUser,
      uint256 operatorChange,
      uint256 timestamp,
      uint256 superblockHeight,
      uint32[] memory selectedUtxos,
      bytes20 operatorPublicKeyHash,
      bool completed
    )
  {
    Unlock storage unlock = getValidUnlock(index);
    from = unlock.from;
    dogeAddress = unlock.dogeAddress;
    valueToUser = unlock.valueToUser;
    operatorChange = unlock.operatorChange;
    timestamp = unlock.timestamp;
    superblockHeight = unlock.superblockHeight;
    selectedUtxos = unlock.selectedUtxos;
    operatorPublicKeyHash = unlock.operatorPublicKeyHash;
    completed = unlock.completed;
  }

  // Unlock section end

  function getUtxosLength(bytes20 operatorPublicKeyHash) public view returns (uint256) {
    Operator storage operator = operators[operatorPublicKeyHash];
    return operator.utxos.length;
  }

  function getUtxo(bytes20 operatorPublicKeyHash, uint256 i)
    public
    view
    returns (
      uint256 value,
      uint256 txHash,
      uint32 index
    )
  {
    Operator storage operator = operators[operatorPublicKeyHash];
    Utxo storage utxo = operator.utxos[i];
    return (utxo.value, utxo.txHash, utxo.index);
  }

  function getListOfOperators() public view returns (Operator[] memory listOfOperators) {
    uint256 countEnabledOperators = 0;

    for (uint256 i = 0; i < operatorKeys.length; i++) {
      if (!operatorKeys[i].deleted) {
        countEnabledOperators++;
      }
    }

    listOfOperators = new Operator[](countEnabledOperators);
    uint256 j = 0;

    for (uint256 i = 0; i < operatorKeys.length; i++) {
      OperatorKey storage opKey = operatorKeys[i];
      if (!opKey.deleted) {
        listOfOperators[j] = operators[opKey.key];
        j++;
      }
    }

    return listOfOperators;
  }
}

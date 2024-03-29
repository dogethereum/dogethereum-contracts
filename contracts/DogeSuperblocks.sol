// SPDX-License-Identifier: MIT

pragma abicoder v2;
pragma solidity ^0.7.6;

import {DogeMessageLibrary} from "./DogeParser/DogeMessageLibrary.sol";
import {DogeErrorCodes} from "./DogeErrorCodes.sol";
import {TransactionProcessor} from "./TransactionProcessor.sol";

// @dev - Manages superblocks
//
// Management of superblocks and status transitions
contract DogeSuperblocks is DogeErrorCodes {
  // @dev - Superblock status
  enum Status {
    Uninitialized,
    New,
    InBattle,
    SemiApproved,
    Approved,
    Invalid
  }

  // TODO: timestamps in dogecoin fit in 64 bits
  struct SuperblockInfo {
    bytes32 blocksMerkleRoot;
    uint256 accumulatedWork;
    uint256 timestamp;
    uint256 prevTimestamp;
    bytes32 lastHash;
    bytes32 parentId;
    address submitter;
    bytes32 ancestors;
    uint32 lastBits;
    uint32 index;
    uint32 height;
    Status status;
  }

  // Mapping superblock id => superblock data
  mapping(bytes32 => SuperblockInfo) public superblocks;

  // Index to superblock id
  mapping(uint32 => bytes32) private indexSuperblock;
  uint32 indexNextSuperblock;

  bytes32 public bestSuperblock;
  uint256 public bestSuperblockAccumulatedWork;

  event NewSuperblock(bytes32 superblockHash, address who);
  event ApprovedSuperblock(bytes32 superblockHash, address who);
  event ChallengeSuperblock(bytes32 superblockHash, address who);
  event SemiApprovedSuperblock(bytes32 superblockHash, address who);
  event InvalidSuperblock(bytes32 superblockHash, address who);

  event RelayTransaction(bytes32 txHash);

  // SuperblockClaims
  address public trustedSuperblockClaims;

  modifier onlySuperblockClaims() {
    // Error: Only the SuperblockClaims contract can access this function.
    require(msg.sender == trustedSuperblockClaims, "ERR_AUTH_ONLY_SUPERBLOCKCLAIMS");
    _;
  }

  // @dev - sets SuperblockClaims instance associated with managing superblocks.
  // Once trustedSuperblockClaims has been set, it cannot be changed.
  // @param superblockClaims - address of the SuperblockClaims contract to be associated with
  function setSuperblockClaims(address superblockClaims) public {
    require(address(trustedSuperblockClaims) == address(0x0) && superblockClaims != address(0x0));
    trustedSuperblockClaims = superblockClaims;
  }

  // @dev - Initializes superblocks contract
  //
  // Initializes the superblock contract. It can only be called once.
  //
  // @param blocksMerkleRoot Root of the merkle tree of blocks contained in a superblock
  // @param accumulatedWork Accumulated proof of work of the last block in the superblock
  // @param timestamp Timestamp of the last block in the superblock
  // @param prevTimestamp Timestamp of the block previous to the last
  // @param lastHash Hash of the last block in the superblock
  // @param lastBits Difficulty bits of the last block in the superblock
  // @param parentId Id of the parent superblock
  // @return superblockHash
  function initialize(
    bytes32 blocksMerkleRoot,
    uint256 accumulatedWork,
    uint256 timestamp,
    uint256 prevTimestamp,
    bytes32 lastHash,
    uint32 lastBits,
    bytes32 parentId
  ) public returns (bytes32) {
    require(bestSuperblock == 0);
    require(parentId == 0);

    bytes32 superblockHash = calcSuperblockHash(
      blocksMerkleRoot,
      accumulatedWork,
      timestamp,
      prevTimestamp,
      lastHash,
      lastBits,
      parentId
    );
    SuperblockInfo storage superblock = superblocks[superblockHash];

    require(superblock.status == Status.Uninitialized);

    indexSuperblock[indexNextSuperblock] = superblockHash;

    superblock.blocksMerkleRoot = blocksMerkleRoot;
    superblock.accumulatedWork = accumulatedWork;
    superblock.timestamp = timestamp;
    superblock.prevTimestamp = prevTimestamp;
    superblock.lastHash = lastHash;
    superblock.parentId = parentId;
    superblock.submitter = msg.sender;
    superblock.index = indexNextSuperblock;
    superblock.height = 1;
    superblock.lastBits = lastBits;
    superblock.status = Status.Approved;
    superblock.ancestors = 0x0;

    indexNextSuperblock++;

    emit NewSuperblock(superblockHash, msg.sender);

    bestSuperblock = superblockHash;
    bestSuperblockAccumulatedWork = accumulatedWork;

    emit ApprovedSuperblock(superblockHash, msg.sender);

    return superblockHash;
  }

  // @dev - Proposes a new superblock
  //
  // To be accepted, a new superblock needs to have its parent
  // either approved or semi-approved.
  //
  // @param blocksMerkleRoot Root of the merkle tree of blocks contained in a superblock
  // @param accumulatedWork Accumulated proof of work of the last block in the superblock
  // @param timestamp Timestamp of the last block in the superblock
  // @param prevTimestamp Timestamp of the last block's parent
  // @param lastHash Hash of the last block in the superblock
  // @param lastBits Difficulty bits of the last block in the superblock
  // @param parentId Id of the parent superblock
  // @return Error code and superblockHash
  function propose(
    bytes32 blocksMerkleRoot,
    uint256 accumulatedWork,
    uint256 timestamp,
    uint256 prevTimestamp,
    bytes32 lastHash,
    uint32 lastBits,
    bytes32 parentId,
    address submitter
  ) public onlySuperblockClaims returns (bytes32) {
    bytes32 superblockHash = calcSuperblockHash(
      blocksMerkleRoot,
      accumulatedWork,
      timestamp,
      prevTimestamp,
      lastHash,
      lastBits,
      parentId
    );

    SuperblockInfo storage parent = superblocks[parentId];
    // Error: The parent superblock must be approved or semiapproved.
    require(
      parent.status == Status.SemiApproved || parent.status == Status.Approved,
      "ERR_PROPOSED_SUPERBLOCK_BAD_PARENT_STATUS"
    );

    SuperblockInfo storage superblock = superblocks[superblockHash];
    // Error: The superblock must not exist already.
    require(superblock.status == Status.Uninitialized, "ERR_PROPOSED_SUPERBLOCK_EXISTS");

    indexSuperblock[indexNextSuperblock] = superblockHash;

    superblock.blocksMerkleRoot = blocksMerkleRoot;
    superblock.accumulatedWork = accumulatedWork;
    superblock.timestamp = timestamp;
    superblock.prevTimestamp = prevTimestamp;
    superblock.lastHash = lastHash;
    superblock.parentId = parentId;
    superblock.submitter = submitter;
    superblock.index = indexNextSuperblock;
    superblock.height = parent.height + 1;
    superblock.lastBits = lastBits;
    superblock.status = Status.New;
    superblock.ancestors = updateAncestors(parent.ancestors, parent.index, parent.height);

    indexNextSuperblock++;

    emit NewSuperblock(superblockHash, submitter);

    return superblockHash;
  }

  // @dev - Confirm a proposed superblock
  //
  // An unchallenged superblock can be confirmed after a timeout.
  // A challenged superblock is confirmed if it has enough descendants
  // in the main chain.
  //
  // @param superblockHash Id of the superblock to confirm
  // @param validator Address requesting superblock confirmation
  // @return Error code and superblockHash
  function confirm(bytes32 superblockHash, address validator)
    public
    onlySuperblockClaims
    returns (bytes32)
  {
    SuperblockInfo storage superblock = superblocks[superblockHash];
    // Error: The superblock must be new or semiapproved.
    require(
      superblock.status == Status.New || superblock.status == Status.SemiApproved,
      "ERR_CONFIRM_SUPERBLOCK_BAD_STATUS"
    );
    SuperblockInfo storage parent = superblocks[superblock.parentId];
    // Error: The parent superblock must be approved.
    require(parent.status == Status.Approved, "ERR_CONFIRM_SUPERBLOCK_BAD_PARENT_STATUS");
    superblock.status = Status.Approved;
    if (superblock.accumulatedWork > bestSuperblockAccumulatedWork) {
      bestSuperblock = superblockHash;
      bestSuperblockAccumulatedWork = superblock.accumulatedWork;
    }
    emit ApprovedSuperblock(superblockHash, validator);
    return superblockHash;
  }

  // @dev - Challenge a proposed superblock
  //
  // A new superblock can be challenged to start a battle
  // to verify the correctness of the data submitted.
  //
  // @param superblockHash Id of the superblock to challenge
  // @param challenger Address requesting a challenge
  // @return Error code and superblockHash
  function challenge(bytes32 superblockHash, address challenger)
    public
    onlySuperblockClaims
    returns (bytes32)
  {
    SuperblockInfo storage superblock = superblocks[superblockHash];
    // Error: Superblocks can only be challenged if new.
    require(
      superblock.status == Status.New || superblock.status == Status.InBattle,
      "ERR_CHALLENGE_SUPERBLOCK_BAD_STATUS"
    );

    if (superblock.status != Status.InBattle) {
      superblock.status = Status.InBattle;
    }
    emit ChallengeSuperblock(superblockHash, challenger);
    return superblockHash;
  }

  // @dev - Semi-approve a challenged superblock
  //
  // A challenged superblock can be marked as semi-approved
  // if it satisfies all the queries or when all challengers have
  // stopped participating.
  //
  // @param superblockHash Id of the superblock to semi-approve
  // @param validator Address requesting semi approval
  // @return Error code and superblockHash
  function semiApprove(bytes32 superblockHash, address validator)
    public
    onlySuperblockClaims
    returns (bytes32)
  {
    SuperblockInfo storage superblock = superblocks[superblockHash];

    // Error: Only new or challenged superblocks can be semiapproved.
    require(
      superblock.status == Status.InBattle || superblock.status == Status.New,
      "ERR_SEMIAPPROVE_SUPERBLOCK_BAD_STATUS"
    );
    superblock.status = Status.SemiApproved;
    emit SemiApprovedSuperblock(superblockHash, validator);
    return superblockHash;
  }

  // @dev - Invalidates a superblock
  //
  // A superblock with incorrect data can be invalidated immediately.
  // Superblocks that are not in the main chain can be invalidated
  // if not enough superblocks follow them, i.e. they don't have
  // enough descendants.
  //
  // @param superblockHash Id of the superblock to invalidate
  // @param validator Address requesting superblock invalidation
  // @return Error code and superblockHash
  function invalidate(bytes32 superblockHash, address validator)
    public
    onlySuperblockClaims
    returns (bytes32)
  {
    SuperblockInfo storage superblock = superblocks[superblockHash];
    // Error: The superblock must be in battle or semiapproved to be invalidated.
    require(
      superblock.status == Status.InBattle || superblock.status == Status.SemiApproved,
      "ERR_INVALIDATE_SUPERBLOCK_BAD_STATUS"
    );
    superblock.status = Status.Invalid;
    emit InvalidSuperblock(superblockHash, validator);
    return superblockHash;
  }

  // @dev - relays transaction `txBytes` to `untrustedMethod`.
  //
  // @param txBytes - transaction bytes
  // @param operatorPublicKeyHash
  // @param txIndex - transaction's index within the block
  // @param txSiblings - transaction's Merkle siblings
  // @param dogeBlockHeader - block header containing transaction
  // @param dogeBlockIndex - block's index withing superblock
  // @param dogeBlockSiblings - block's merkle siblings
  // @param superblockHash - superblock containing block header
  // @param untrustedMethod - the external method that will process the transaction
  function relayTx(
    bytes calldata txBytes,
    bytes20 operatorPublicKeyHash,
    uint256 txIndex,
    uint256[] memory txSiblings,
    bytes memory dogeBlockHeader,
    uint256 dogeBlockIndex,
    uint256[] memory dogeBlockSiblings,
    bytes32 superblockHash,
    function(bytes memory, uint256, bytes20, address) external untrustedMethod
  ) public {
    verifyBlockMembership(dogeBlockHeader, dogeBlockIndex, dogeBlockSiblings, superblockHash);

    uint256 txHash = verifyTx(txBytes, txIndex, txSiblings, dogeBlockHeader, superblockHash);
    untrustedMethod(txBytes, txHash, operatorPublicKeyHash, superblocks[superblockHash].submitter);
    emit RelayTransaction(bytes32(txHash));
  }

  // @dev - relays transaction `txBytes` to `untrustedTargetContract`'s processLockTransaction() method.
  // This function exists solely to offer a compatibility layer for libraries that don't support function
  // types in parameters.
  //
  // @param txBytes - transaction bytes
  // @param operatorPublicKeyHash
  // @param txIndex - transaction's index within the block
  // @param txSiblings - transaction's Merkle siblings
  // @param dogeBlockHeader - block header containing transaction
  // @param dogeBlockIndex - block's index withing superblock
  // @param dogeBlockSiblings - block's merkle siblings
  // @param superblockHash - superblock containing block header
  // @param untrustedTargetContract - the contract that is going to process the lock transaction
  function relayLockTx(
    bytes calldata txBytes,
    bytes20 operatorPublicKeyHash,
    uint256 txIndex,
    uint256[] memory txSiblings,
    bytes memory dogeBlockHeader,
    uint256 dogeBlockIndex,
    uint256[] memory dogeBlockSiblings,
    bytes32 superblockHash,
    TransactionProcessor untrustedTargetContract
  ) public {
    relayTx(
      txBytes,
      operatorPublicKeyHash,
      txIndex,
      txSiblings,
      dogeBlockHeader,
      dogeBlockIndex,
      dogeBlockSiblings,
      superblockHash,
      untrustedTargetContract.processLockTransaction
    );
  }

  // @dev - relays transaction `txBytes` to `untrustedTargetContract`'s processUnlockTransaction() method.
  // This function exists solely to offer a compatibility layer for libraries that don't support function
  // types in parameters.
  //
  // @param txBytes - transaction bytes
  // @param operatorPublicKeyHash
  // @param txIndex - transaction's index within the block
  // @param txSiblings - transaction's Merkle siblings
  // @param dogeBlockHeader - block header containing transaction
  // @param dogeBlockIndex - block's index withing superblock
  // @param dogeBlockSiblings - block's merkle siblings
  // @param superblockHash - superblock containing block header
  // @param untrustedTargetContract - the contract that is going to process the lock transaction
  function relayUnlockTx(
    bytes calldata txBytes,
    bytes20 operatorPublicKeyHash,
    uint256 txIndex,
    uint256[] memory txSiblings,
    bytes memory dogeBlockHeader,
    uint256 dogeBlockIndex,
    uint256[] memory dogeBlockSiblings,
    bytes32 superblockHash,
    TransactionProcessor untrustedTargetContract,
    uint256 unlockIndex
  ) public {
    verifyBlockMembership(dogeBlockHeader, dogeBlockIndex, dogeBlockSiblings, superblockHash);

    uint256 txHash = verifyTx(txBytes, txIndex, txSiblings, dogeBlockHeader, superblockHash);
    untrustedTargetContract.processUnlockTransaction(
      txBytes,
      txHash,
      operatorPublicKeyHash,
      unlockIndex
    );
    emit RelayTransaction(bytes32(txHash));
  }

  // @dev - relays transaction `txBytes` to `untrustedTargetContract`'s processUnlockTransaction() method.
  // This function exists solely to offer a compatibility layer for libraries that don't support function
  // types in parameters.
  //
  // @param txBytes - transaction bytes
  // @param operatorPublicKeyHash
  // @param txIndex - transaction's index within the block
  // @param txSiblings - transaction's Merkle siblings
  // @param dogeBlockHeader - block header containing transaction
  // @param dogeBlockIndex - block's index withing superblock
  // @param dogeBlockSiblings - block's merkle siblings
  // @param superblockHash - superblock containing block header
  // @param untrustedTargetContract - the contract that is going to process the lock transaction
  function relayTxAndReportOperatorFreeUtxoSpend(
    bytes calldata txBytes,
    bytes20 operatorPublicKeyHash,
    uint256 txIndex,
    uint256[] memory txSiblings,
    bytes memory dogeBlockHeader,
    uint256 dogeBlockIndex,
    uint256[] memory dogeBlockSiblings,
    bytes32 superblockHash,
    TransactionProcessor untrustedTargetContract,
    uint32 operatorTxOutputReference,
    uint32 unlawfulTxInputIndex
  ) public {
    verifyBlockMembership(dogeBlockHeader, dogeBlockIndex, dogeBlockSiblings, superblockHash);

    uint256 txHash = verifyTx(txBytes, txIndex, txSiblings, dogeBlockHeader, superblockHash);
    untrustedTargetContract.processReportOperatorFreeUtxoSpend(
      txBytes,
      txHash,
      operatorPublicKeyHash,
      operatorTxOutputReference,
      unlawfulTxInputIndex
    );
    emit RelayTransaction(bytes32(txHash));
  }

  /**
   * Check if Doge block belongs to given superblock
   */
  function verifyBlockMembership(
    bytes memory dogeBlockHeader,
    uint256 dogeBlockIndex,
    uint256[] memory dogeBlockSiblings,
    bytes32 superblockHash
  ) internal view {
    uint256 dogeBlockHash = DogeMessageLibrary.dblShaFlip(dogeBlockHeader);

    require(
      bytes32(DogeMessageLibrary.computeMerkle(dogeBlockHash, dogeBlockIndex, dogeBlockSiblings)) ==
        getSuperblockMerkleRoot(superblockHash),
      "Doge block does not belong to superblock"
    );
  }

  // @dev - Checks whether the transaction given by `txBytes` is in the block identified by `txBlockHash`
  // and whether the block is in the Dogecoin main chain. Transaction check is done via Merkle proof.
  //
  // @param txBytes - transaction bytes
  // @param txIndex - transaction's index within the block
  // @param siblings - transaction's Merkle siblings
  // @param blockHeader - block header containing transaction
  // @param superblockHash - superblock containing block header
  // @return - SHA-256 hash of txBytes if the transaction is in the block, 0 otherwise
  // TODO: this can probably be made private
  function verifyTx(
    bytes memory txBytes,
    uint256 txIndex,
    uint256[] memory siblings,
    bytes memory blockHeader,
    bytes32 superblockHash
  ) public view returns (uint256) {
    uint256 txHash = DogeMessageLibrary.dblShaFlip(txBytes);

    // Attack on Merkle tree mitigations

    // This guards against a Merkle tree collision attack if the transaction is exactly 64 bytes long,
    // TODO: are 32 bytes long transactions also a problem?
    require(txBytes.length != 64, "Transactions of exactly 64 bytes cannot be accepted.");

    // Merkle tree verification

    // TODO: implement when dealing with incentives
    // require(feePaid(txBlockHash, getFeeAmount(txBlockHash)));

    // Verify superblock is in superblock's main chain
    require(isApproved(superblockHash), "Superblock is not approved");
    require(inMainChain(superblockHash), "Superblock is not part of the main chain");

    // Verify tx Merkle root
    uint256 merkle = DogeMessageLibrary.getHeaderMerkleRoot(blockHeader, 0);
    uint256 computedMerkle = DogeMessageLibrary.computeMerkle(txHash, txIndex, siblings);
    require(computedMerkle == merkle, "Tx merkle proof is invalid");
    return txHash;
  }

  // @dev - Calculate superblock hash from superblock data
  //
  // @param blocksMerkleRoot Root of the merkle tree of blocks contained in a superblock
  // @param accumulatedWork Accumulated proof of work of the last block in the superblock
  // @param timestamp Timestamp of the last block in the superblock
  // @param prevTimestamp Timestamp of the block previous to the last
  // @param lastHash Hash of the last block in the superblock
  // @param lastBits Difficulty bits of the last block in the superblock
  // @param parentId Id of the parent superblock
  // @return Superblock id
  function calcSuperblockHash(
    bytes32 blocksMerkleRoot,
    uint256 accumulatedWork,
    uint256 timestamp,
    uint256 prevTimestamp,
    bytes32 lastHash,
    uint32 lastBits,
    bytes32 parentId
  ) public pure returns (bytes32) {
    return
      keccak256(
        abi.encodePacked(
          blocksMerkleRoot,
          accumulatedWork,
          timestamp,
          prevTimestamp,
          lastHash,
          lastBits,
          parentId
        )
      );
  }

  // @dev - Returns the confirmed superblock with the most accumulated work
  //
  // @return Best superblock hash
  function getBestSuperblock() public view returns (bytes32) {
    return bestSuperblock;
  }

  // @dev - Returns the superblock data for the supplied superblock hash
  //
  // @return {
  //   bytes32 blocksMerkleRoot,
  //   uint accumulatedWork,
  //   uint timestamp,
  //   uint prevTimestamp,
  //   bytes32 lastHash,
  //   uint32 lastBits,
  //   bytes32 parentId,
  //   address submitter,
  //   Status status
  // }  Superblock data
  function getSuperblock(bytes32 superblockHash)
    public
    view
    returns (
      bytes32 blocksMerkleRoot,
      uint256 accumulatedWork,
      uint256 timestamp,
      uint256 prevTimestamp,
      bytes32 lastHash,
      uint32 lastBits,
      bytes32 parentId,
      address submitter,
      Status status
    )
  {
    SuperblockInfo storage superblock = superblocks[superblockHash];
    return (
      superblock.blocksMerkleRoot,
      superblock.accumulatedWork,
      superblock.timestamp,
      superblock.prevTimestamp,
      superblock.lastHash,
      superblock.lastBits,
      superblock.parentId,
      superblock.submitter,
      superblock.status
    );
  }

  // @dev - Returns superblock height
  function getSuperblockHeight(bytes32 superblockHash) public view returns (uint32) {
    return superblocks[superblockHash].height;
  }

  // @dev - Returns superblock internal index
  function getSuperblockIndex(bytes32 superblockHash) public view returns (uint32) {
    return superblocks[superblockHash].index;
  }

  // @dev - Return superblock ancestors' indexes
  function getSuperblockAncestors(bytes32 superblockHash) public view returns (bytes32) {
    return superblocks[superblockHash].ancestors;
  }

  // @dev - Return superblock blocks' Merkle root
  function getSuperblockMerkleRoot(bytes32 superblockHash) public view returns (bytes32) {
    return superblocks[superblockHash].blocksMerkleRoot;
  }

  // @dev - Return superblock timestamp
  function getSuperblockTimestamp(bytes32 superblockHash) public view returns (uint256) {
    return superblocks[superblockHash].timestamp;
  }

  // @dev - Return superblock prevTimestamp
  function getSuperblockPrevTimestamp(bytes32 superblockHash) public view returns (uint256) {
    return superblocks[superblockHash].prevTimestamp;
  }

  // @dev - Return superblock last block hash
  function getSuperblockLastHash(bytes32 superblockHash) public view returns (bytes32) {
    return superblocks[superblockHash].lastHash;
  }

  // @dev - Return superblock parent
  function getSuperblockParentId(bytes32 superblockHash) public view returns (bytes32) {
    return superblocks[superblockHash].parentId;
  }

  // @dev - Return superblock accumulated work
  function getSuperblockAccumulatedWork(bytes32 superblockHash) public view returns (uint256) {
    return superblocks[superblockHash].accumulatedWork;
  }

  // @dev - Return superblock status
  function getSuperblockStatus(bytes32 superblockHash) public view returns (Status) {
    return superblocks[superblockHash].status;
  }

  // @dev - Return indexNextSuperblock
  function getIndexNextSuperblock() public view returns (uint32) {
    return indexNextSuperblock;
  }

  // @dev - Calculate Merkle root from Doge block hashes
  function makeMerkle(bytes32[] calldata hashes) public pure returns (bytes32) {
    return DogeMessageLibrary.makeMerkle(hashes);
  }

  function isApproved(bytes32 superblockHash) public view returns (bool) {
    return (getSuperblockStatus(superblockHash) == Status.Approved);
  }

  function getChainHeight() public view returns (uint256) {
    return superblocks[bestSuperblock].height;
  }

  // @dev - write `fourBytes` into `word` starting from `position`
  // This is useful for writing 32bit ints inside one 32 byte word
  //
  // @param word - information to be partially overwritten
  // @param position - position to start writing from
  // @param fourBytes - information to be written
  function writeUint32(
    bytes32 word,
    uint256 position,
    uint32 fourBytes
  ) private pure returns (bytes32) {
    bytes32 result;
    assembly {
      let pointer := mload(0x40)
      mstore(pointer, word)
      mstore8(add(pointer, position), byte(28, fourBytes))
      mstore8(add(pointer, add(position, 1)), byte(29, fourBytes))
      mstore8(add(pointer, add(position, 2)), byte(30, fourBytes))
      mstore8(add(pointer, add(position, 3)), byte(31, fourBytes))
      result := mload(pointer)
    }
    return result;
  }

  uint256 constant ANCESTOR_STEP = 5;
  uint256 constant NUM_ANCESTOR_DEPTHS = 8;

  // @dev - Update ancestor to the new height
  function updateAncestors(
    bytes32 ancestors,
    uint32 index,
    uint256 height
  ) internal pure returns (bytes32) {
    uint256 step = ANCESTOR_STEP;
    ancestors = writeUint32(ancestors, 0, index);
    uint256 i = 1;
    while (i < NUM_ANCESTOR_DEPTHS && (height % step == 1)) {
      ancestors = writeUint32(ancestors, 4 * i, index);
      step *= ANCESTOR_STEP;
      ++i;
    }
    return ancestors;
  }

  // @dev - Returns a list of superblock hashes (9 hashes maximum) that helps an agent find out what
  // superblocks are missing.
  // The first position contains bestSuperblock, then
  // bestSuperblock - 1,
  // (bestSuperblock-1) - ((bestSuperblock-1) % 5), then
  // (bestSuperblock-1) - ((bestSuperblock-1) % 25), ... until
  // (bestSuperblock-1) - ((bestSuperblock-1) % 78125)
  //
  // @return - list of up to 9 ancestor supeerblock id
  function getSuperblockLocator() public view returns (bytes32[9] memory) {
    bytes32[9] memory locator;
    locator[0] = bestSuperblock;
    bytes32 ancestors = getSuperblockAncestors(bestSuperblock);
    uint256 i = NUM_ANCESTOR_DEPTHS;
    while (i > 0) {
      locator[i] = indexSuperblock[uint32(uint256(ancestors) & 0xFFFFFFFF)];
      ancestors >>= 32;
      --i;
    }
    return locator;
  }

  // @dev - Return ancestor at given index
  function getSuperblockAncestor(bytes32 superblockHash, uint256 index)
    internal
    view
    returns (bytes32)
  {
    bytes32 ancestors = superblocks[superblockHash].ancestors;
    uint32 ancestorsIndex = uint32(uint8(ancestors[4 * index + 0])) *
      0x1000000 +
      uint32(uint8(ancestors[4 * index + 1])) *
      0x10000 +
      uint32(uint8(ancestors[4 * index + 2])) *
      0x100 +
      uint32(uint8(ancestors[4 * index + 3])) *
      0x1;
    return indexSuperblock[ancestorsIndex];
  }

  // dev - returns depth associated with an ancestor index; applies to any superblock
  //
  // @param index - index of ancestor to be looked up; an integer between 0 and 7
  // @return - depth corresponding to said index, i.e. 5**index
  function getAncDepth(uint256 index) private pure returns (uint256) {
    return ANCESTOR_STEP**(uint256(index));
  }

  // @dev - return superblock hash at a given height in superblock main chain
  //
  // @param height - superblock height
  // @return - hash corresponding to block of given height
  function getSuperblockAt(uint256 height) public view returns (bytes32) {
    bytes32 superblockHash = bestSuperblock;
    uint256 index = NUM_ANCESTOR_DEPTHS - 1;

    uint256 currentHeight = getSuperblockHeight(superblockHash);
    while (currentHeight > height) {
      while (currentHeight - height < getAncDepth(index) && index > 0) {
        index -= 1;
      }
      superblockHash = getSuperblockAncestor(superblockHash, index);
      currentHeight = getSuperblockHeight(superblockHash);
    }

    return superblockHash;
  }

  // @dev - Checks if a superblock is in superblock main chain
  //
  // @param superblockHash - hash of the block being searched for in the main chain
  // @return - true if the block identified by superblockHash is in the main chain,
  // false otherwise
  function inMainChain(bytes32 superblockHash) internal view returns (bool) {
    uint256 height = getSuperblockHeight(superblockHash);
    if (height == 0) return false;
    return (getSuperblockAt(height) == superblockHash);
  }
}

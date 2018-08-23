pragma solidity ^0.4.19;

import {DogeTx} from "./DogeParser/DogeTx.sol";
import {DogeErrorCodes} from "./DogeErrorCodes.sol";
import {TransactionProcessor} from "./TransactionProcessor.sol";


// @dev - Manages superblocks
//
// Management of superblocks and status transitions
contract DogeSuperblocks is DogeErrorCodes {

    // @dev - Superblock status
    enum Status { Unitialized, New, InBattle, SemiApproved, Approved, Invalid }

    struct SuperblockInfo {
        bytes32 blocksMerkleRoot;
        uint accumulatedWork;
        uint timestamp;
        uint prevTimestamp;
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
    mapping (bytes32 => SuperblockInfo) superblocks;

    // Index to superblock id
    mapping (uint32 => bytes32) private indexSuperblock;
    uint32 indexNextSuperblock;

    bytes32 public bestSuperblock;
    uint public bestSuperblockAccumulatedWork;

    //FIXME: Add 'indexed' to parameters
    event NewSuperblock(bytes32 superblockId, address who);
    event ApprovedSuperblock(bytes32 superblockId, address who);
    event ChallengeSuperblock(bytes32 superblockId, address who);
    event SemiApprovedSuperblock(bytes32 superblockId, address who);
    event InvalidSuperblock(bytes32 superblockId, address who);

    event ErrorSuperblock(bytes32 superblockId, uint err);

    event VerifyTransaction(bytes32 txHash, uint returnCode);
    event RelayTransaction(bytes32 txHash, uint returnCode);

    // ClaimManager
    address public claimManager;

    modifier onlyClaimManager() {
        require(msg.sender == claimManager);
        _;
    }

    // @dev – the constructor
    constructor() public {}

    // @dev - sets ClaimManager instance associated with managing superblocks.
    // Once claimManager has been set, it cannot be changed.
    // @param _claimManager - address of the ClaimManager contract to be associated with
    function setClaimManager(address _claimManager) public {
        require(address(claimManager) == 0x0 && _claimManager != 0x0);
        claimManager = _claimManager;
    }

    // @dev - Initializes superblocks contract
    //
    // Initializes the superblock contract. It can only be called once.
    //
    // @param _blocksMerkleRoot Root of the merkle tree of blocks contained in a superblock
    // @param _accumulatedWork Accumulated proof of work of the last block in the superblock
    // @param _timestamp Timestamp of the last block in the superblock
    // @param _prevTimestamp Timestamp of the block previous to the last
    // @param _lastHash Hash of the last block in the superblock
    // @param _lastBits Difficulty bits of the last block in the superblock
    // @param _parentId Id of the parent superblock
    // @return Error code and superblockId
    function initialize(bytes32 _blocksMerkleRoot, uint _accumulatedWork, uint _timestamp, uint _prevTimestamp, bytes32 _lastHash, uint32 _lastBits, bytes32 _parentId) public returns (uint, bytes32) {
        require(bestSuperblock == 0);
        require(_parentId == 0);

        bytes32 superblockId = calcSuperblockId(_blocksMerkleRoot, _accumulatedWork, _timestamp, _prevTimestamp, _lastHash, _lastBits, _parentId);
        SuperblockInfo storage superblock = superblocks[superblockId];

        require(superblock.status == Status.Unitialized);

        indexSuperblock[indexNextSuperblock] = superblockId;

        superblock.blocksMerkleRoot = _blocksMerkleRoot;
        superblock.accumulatedWork = _accumulatedWork;
        superblock.timestamp = _timestamp;
        superblock.prevTimestamp = _prevTimestamp;
        superblock.lastHash = _lastHash;
        superblock.parentId = _parentId;
        superblock.submitter = msg.sender;
        superblock.index = indexNextSuperblock;
        superblock.height = 0;
        superblock.lastBits = _lastBits;
        superblock.status = Status.Approved;
        superblock.ancestors = 0x0;

        indexNextSuperblock++;

        emit NewSuperblock(superblockId, msg.sender);

        bestSuperblock = superblockId;
        bestSuperblockAccumulatedWork = _accumulatedWork;

        emit ApprovedSuperblock(superblockId, msg.sender);

        return (ERR_SUPERBLOCK_OK, superblockId);
    }

    // @dev - Proposes a new superblock
    //
    // A new superblock to be accepted it has to have a parent superblock
    // approved or semi approved.
    //
    // @param _blocksMerkleRoot Root of the merkle tree of blocks contained in a superblock
    // @param _accumulatedWork Accumulated proof of work of the last block in the superblock
    // @param _timestamp Timestamp of the last block in the superblock
    // @param _prevTimestamp Timestamp of the block previous to the last
    // @param _lastHash Hash of the last block in the superblock
    // @param _lastBits Difficulty bits of the last block in the superblock
    // @param _parentId Id of the parent superblock
    // @return Error code and superblockId
    function propose(bytes32 _blocksMerkleRoot, uint _accumulatedWork, uint _timestamp, uint _prevTimestamp, bytes32 _lastHash, uint32 _lastBits, bytes32 _parentId, address submitter) public returns (uint, bytes32) {
        if (msg.sender != claimManager) {
            emit ErrorSuperblock(0, ERR_SUPERBLOCK_NOT_CLAIMMANAGER);
            return (ERR_SUPERBLOCK_NOT_CLAIMMANAGER, 0);
        }

        SuperblockInfo storage parent = superblocks[_parentId];
        if (parent.status != Status.SemiApproved && parent.status != Status.Approved) {
            emit ErrorSuperblock(superblockId, ERR_SUPERBLOCK_BAD_PARENT);
            return (ERR_SUPERBLOCK_BAD_PARENT, 0);
        }

        bytes32 superblockId = calcSuperblockId(_blocksMerkleRoot, _accumulatedWork, _timestamp, _prevTimestamp, _lastHash, _lastBits, _parentId);
        SuperblockInfo storage superblock = superblocks[superblockId];
        if (superblock.status != Status.Unitialized) {
            emit ErrorSuperblock(superblockId, ERR_SUPERBLOCK_EXIST);
            return (ERR_SUPERBLOCK_EXIST, 0);
        }

        indexSuperblock[indexNextSuperblock] = superblockId;

        superblock.blocksMerkleRoot = _blocksMerkleRoot;
        superblock.accumulatedWork = _accumulatedWork;
        superblock.timestamp = _timestamp;
        superblock.prevTimestamp = _prevTimestamp;
        superblock.lastHash = _lastHash;
        superblock.parentId = _parentId;
        superblock.submitter = submitter;
        superblock.index = indexNextSuperblock;
        superblock.height = parent.height + 1;
        superblock.lastBits = _lastBits;
        superblock.status = Status.New;
        superblock.ancestors = updateAncestors(parent.ancestors, parent.index, parent.height + 1);

        indexNextSuperblock++;

        emit NewSuperblock(superblockId, submitter);

        return (ERR_SUPERBLOCK_OK, superblockId);
    }

    // @dev - Confirm a proposed superblock
    //
    // An unchallenged superblock can be confirmed after a timeout.
    // A challenged superblock is confirmed if it has enough superblocks
    // in the main chain.
    //
    // @param _superblockId Id of the superblock to confirm
    // @return Error code and superblockId
    function confirm(bytes32 _superblockId, address validator) public returns (uint, bytes32) {
        if (msg.sender != claimManager) {
            emit ErrorSuperblock(_superblockId, ERR_SUPERBLOCK_NOT_CLAIMMANAGER);
            return (ERR_SUPERBLOCK_NOT_CLAIMMANAGER, 0);
        }
        SuperblockInfo storage superblock = superblocks[_superblockId];
        if (superblock.status != Status.New && superblock.status != Status.SemiApproved) {
            emit ErrorSuperblock(_superblockId, ERR_SUPERBLOCK_BAD_STATUS);
            return (ERR_SUPERBLOCK_BAD_STATUS, 0);
        }
        SuperblockInfo storage parent = superblocks[superblock.parentId];
        if (parent.status != Status.Approved) {
            emit ErrorSuperblock(_superblockId, ERR_SUPERBLOCK_BAD_PARENT);
            return (ERR_SUPERBLOCK_BAD_PARENT, 0);
        }
        superblock.status = Status.Approved;
        if (superblock.accumulatedWork > bestSuperblockAccumulatedWork) {
            bestSuperblock = _superblockId;
            bestSuperblockAccumulatedWork = superblock.accumulatedWork;
        }
        emit ApprovedSuperblock(_superblockId, validator);
        return (ERR_SUPERBLOCK_OK, _superblockId);
    }

    // @dev - Challenge a proposed superblock
    //
    // A new superblock can be challenged to start a battle
    // to verify the correctness of the data submitted.
    //
    // @param _superblockId Id of the superblock to challenge
    // @return Error code and superblockId
    function challenge(bytes32 _superblockId, address challenger) public returns (uint, bytes32) {
        if (msg.sender != claimManager) {
            emit ErrorSuperblock(_superblockId, ERR_SUPERBLOCK_NOT_CLAIMMANAGER);
            return (ERR_SUPERBLOCK_NOT_CLAIMMANAGER, 0);
        }
        SuperblockInfo storage superblock = superblocks[_superblockId];
        if (superblock.status != Status.New && superblock.status != Status.InBattle) {
            emit ErrorSuperblock(_superblockId, ERR_SUPERBLOCK_BAD_STATUS);
            return (ERR_SUPERBLOCK_BAD_STATUS, 0);
        }
        superblock.status = Status.InBattle;
        emit ChallengeSuperblock(_superblockId, challenger);
        return (ERR_SUPERBLOCK_OK, _superblockId);
    }

    // @dev - Semi-approve a challenged superblock
    //
    // A challenged superblock can be marked as semi-approved
    // if it satisfies all the queries or when all challengers have
    // stopped participating.
    //
    // @param _superblockId Id of the superblock to semi-approve
    // @return Error code and superblockId
    function semiApprove(bytes32 _superblockId, address validator) public returns (uint, bytes32) {
        if (msg.sender != claimManager) {
            emit ErrorSuperblock(_superblockId, ERR_SUPERBLOCK_NOT_CLAIMMANAGER);
            return (ERR_SUPERBLOCK_NOT_CLAIMMANAGER, 0);
        }
        SuperblockInfo storage superblock = superblocks[_superblockId];

        if (superblock.status != Status.InBattle && superblock.status != Status.New) {
            emit ErrorSuperblock(_superblockId, ERR_SUPERBLOCK_BAD_STATUS);
            return (ERR_SUPERBLOCK_BAD_STATUS, 0);
        }
        superblock.status = Status.SemiApproved;
        emit SemiApprovedSuperblock(_superblockId, validator);
        return (ERR_SUPERBLOCK_OK, _superblockId);
    }

    // @dev - Invalidates a superblock
    //
    // A superblock with incorrect data can be invalidated immediately.
    // Superblocks that are not in the main chain can be invalidates
    // if not enough superblocks follows them.
    //
    // @param _superblockId Id of the superblock to invalidate
    // @return Error code and superblockId
    function invalidate(bytes32 _superblockId, address validator) public returns (uint, bytes32) {
        if (msg.sender != claimManager) {
            emit ErrorSuperblock(_superblockId, ERR_SUPERBLOCK_NOT_CLAIMMANAGER);
            return (ERR_SUPERBLOCK_NOT_CLAIMMANAGER, 0);
        }
        SuperblockInfo storage superblock = superblocks[_superblockId];
        if (superblock.status != Status.InBattle && superblock.status != Status.SemiApproved) {
            emit ErrorSuperblock(_superblockId, ERR_SUPERBLOCK_BAD_STATUS);
            return (ERR_SUPERBLOCK_BAD_STATUS, 0);
        }
        superblock.status = Status.Invalid;
        emit InvalidSuperblock(_superblockId, validator);
        return (ERR_SUPERBLOCK_OK, _superblockId);
    }

    // @dev - relays transaction `_txBytes` to `_targetContract`'s processTransaction() method.
    // Also logs the value of processTransaction.
    // Note: callers cannot be 100% certain when an ERR_RELAY_VERIFY occurs because
    // it may also have been returned by processTransaction(). Callers should be
    // aware of the contract that they are relaying transactions to and
    // understand what that contract's processTransaction method returns.
    //
    // @param _txBytes - transaction bytes
    // @param _operatorPublicKeyHash
    // @param _txIndex - transaction's index within the block
    // @param _txSiblings - transaction's Merkle siblings
    // @param _dogeBlockHeader - block header containing transaction
    // @param _dogeBlockIndex - block's index withing superblock
    // @param _dogeBlockSiblings - block's merkle siblings
    // @param _superblockId - superblock containing block header
    // @param _targetContract -
    function relayTx(
        bytes _txBytes,
        bytes20 _operatorPublicKeyHash,
        uint _txIndex,
        uint[] _txSiblings,
        bytes _dogeBlockHeader,
        uint _dogeBlockIndex,
        uint[] _dogeBlockSiblings,
        bytes32 _superblockId,
        TransactionProcessor _targetContract
    ) public returns (uint) {
        uint dogeBlockHash = DogeTx.dblShaFlip(_dogeBlockHeader);

        // Check if Doge block belongs to given superblock
        if (bytes32(DogeTx.computeMerkle(dogeBlockHash, _dogeBlockIndex, _dogeBlockSiblings))
            != getSuperblockMerkleRoot(_superblockId)) {
            // Doge block is not in superblock
            emit VerifyTransaction(bytes32(DogeTx.dblShaFlip(_txBytes)), ERR_SUPERBLOCK);
            return ERR_SUPERBLOCK;
        }

        uint txHash = verifyTx(_txBytes, _txIndex, _txSiblings, _dogeBlockHeader, _superblockId);
        if (txHash != 0) {
            uint returnCode = _targetContract.processTransaction(_txBytes, txHash, _operatorPublicKeyHash, superblocks[_superblockId].submitter);
            emit RelayTransaction(bytes32(txHash), returnCode);
            return (returnCode);
        }

        emit RelayTransaction(bytes32(0), ERR_RELAY_VERIFY);
        return(ERR_RELAY_VERIFY);
    }

    // @dev - Checks whether the transaction given by `_txBytes` is in the block identified by `_txBlockHash`.
    // First it guards against a Merkle tree collision attack by raising an error if the transaction is exactly 64 bytes long,
    // then it calls helperVerifyHash to do the actual check.
    //
    // @param _txBytes - transaction bytes
    // @param _txIndex - transaction's index within the block
    // @param _siblings - transaction's Merkle siblings
    // @param _txBlockHeaderBytes - block header containing transaction
    // @param _txSuperblockId - superblock containing block header
    // @return - SHA-256 hash of _txBytes if the transaction is in the block, 0 otherwise
    function verifyTx(
        bytes _txBytes,
        uint _txIndex,
        uint[] _siblings,
        bytes _txBlockHeaderBytes,
        bytes32 _txSuperblockId
    ) public returns (uint) {
        uint txHash = DogeTx.dblShaFlip(_txBytes);

        if (_txBytes.length == 64) {  // todo: is check 32 also needed?
            emit VerifyTransaction(bytes32(txHash), ERR_TX_64BYTE);
            return 0;
        }

        if (helperVerifyHash(txHash, _txIndex, _siblings, _txBlockHeaderBytes, _txSuperblockId) == 1) {
            return txHash;
        } else {
            // log is done via helperVerifyHash
            return 0;
        }
    }

    // @dev - Checks whether the transaction identified by `_txHash` is in the block identified by `_txBlockHash`
    // and whether the block is in Dogecoin's main chain. Transaction check is done via Merkle proof.
    // Note: no verification is performed to prevent txHash from just being an
    // internal hash in the Merkle tree. Thus this helper method should NOT be used
    // directly and is intended to be private.
    //
    // @param _txHash - transaction hash
    // @param _txIndex - transaction's index within the block
    // @param _siblings - transaction's Merkle siblings
    // @param _blockHeaderBytes - block header containing transaction
    // @param _txSuperblockId - superblock containing block header
    // @return - 1 if the transaction is in the block and the block is in the main chain,
    // 20020 (ERR_CONFIRMATIONS) if the block is not in the main chain,
    // 20050 (ERR_MERKLE_ROOT) if the block is in the main chain but the Merkle proof fails.
    function helperVerifyHash(
        uint256 _txHash,
        uint _txIndex,
        uint[] _siblings,
        bytes _blockHeaderBytes,
        bytes32 _txSuperblockId
    ) private returns (uint) {
        // TODO: implement when dealing with incentives
        // if (!feePaid(_txBlockHash, getFeeAmount(_txBlockHash))) {  // in incentive.se
        //    VerifyTransaction(bytes32(_txHash), ERR_BAD_FEE);
        //    return (ERR_BAD_FEE);
        // }

        //TODO: Verify superblock is in superblock's main chain
        if (!isApproved(_txSuperblockId)) {
            emit VerifyTransaction(bytes32(_txHash), ERR_CHAIN);
            return (ERR_CHAIN);
        }

        // Verify tx Merkle root
        uint merkle = DogeTx.getHeaderMerkleRoot(_blockHeaderBytes, 0);
        if (DogeTx.computeMerkle(_txHash, _txIndex, _siblings) != merkle) {
            emit VerifyTransaction(bytes32(_txHash), ERR_MERKLE_ROOT);
            return (ERR_MERKLE_ROOT);
        }

        emit VerifyTransaction(bytes32(_txHash), 1);
        return (1);
    }

    // @dev - Evaluate the SuperblockId
    //
    // Evaluate the SuperblockId given the superblock data.
    //
    // @param _blocksMerkleRoot Root of the merkle tree of blocks contained in a superblock
    // @param _accumulatedWork Accumulated proof of work of the last block in the superblock
    // @param _timestamp Timestamp of the last block in the superblock
    // @param _prevTimestamp Timestamp of the block previous to the last
    // @param _lastHash Hash of the last block in the superblock
    // @param _lastBits Difficulty bits of the last block in the superblock
    // @param _parentId Id of the parent superblock
    // @return Superblock id
    function calcSuperblockId(bytes32 _blocksMerkleRoot, uint _accumulatedWork, uint _timestamp, uint _prevTimestamp, bytes32 _lastHash, uint32 _lastBits, bytes32 _parentId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_blocksMerkleRoot, _accumulatedWork, _timestamp, _prevTimestamp, _lastHash, _lastBits, _parentId));
    }

    // @dev - Returns the confirmed superblock with the most accumulated work
    //
    // @return Superblock id
    function getBestSuperblock() public view returns (bytes32) {
        return bestSuperblock;
    }

    // @dev - Returns the superblock data for the supplied superblockId
    //
    // @return {
    //   bytes32 _blocksMerkleRoot,
    //   uint _accumulatedWork,
    //   uint _timestamp,
    //   uint _prevTimestamp,
    //   bytes32 _lastHash,
    //   uint32 _lastBits,
    //   bytes32 _parentId,
    //   address _submitter,
    //   Status _status
    // }  Superblock data
    function getSuperblock(bytes32 superblockId) public view returns (
        bytes32 _blocksMerkleRoot,
        uint _accumulatedWork,
        uint _timestamp,
        uint _prevTimestamp,
        bytes32 _lastHash,
        uint32 _lastBits,
        bytes32 _parentId,
        address _submitter,
        Status _status
    ) {
        SuperblockInfo storage superblock = superblocks[superblockId];
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

    // Returns superblock height
    function getSuperblockHeight(bytes32 superblockId) public view returns (uint32) {
        return superblocks[superblockId].height;
    }

    // @dev - Returns superblock internal index
    function getSuperblockIndex(bytes32 superblockId) public view returns (uint32) {
        return superblocks[superblockId].index;
    }

    // @dev - Return superblock ancestors indexes
    function getSuperblockAncestors(bytes32 superblockId) public view returns (bytes32) {
        return superblocks[superblockId].ancestors;
    }

    // @dev - Return superblock blocks' merkle root
    function getSuperblockMerkleRoot(bytes32 _superblockId) public view returns (bytes32) {
        return superblocks[_superblockId].blocksMerkleRoot;
    }

    // @dev - Return superblock timestamp
    function getSuperblockTimestamp(bytes32 _superblockId) public view returns (uint) {
        return superblocks[_superblockId].timestamp;
    }

    // @dev - Return superblock prevTimestamp
    function getSuperblockPrevTimestamp(bytes32 _superblockId) public view returns (uint) {
        return superblocks[_superblockId].prevTimestamp;
    }

    // @dev - Return superblock last block hash
    function getSuperblockLastHash(bytes32 _superblockId) public view returns (bytes32) {
        return superblocks[_superblockId].lastHash;
    }

    // @dev - Return superblock parent
    function getSuperblockParentId(bytes32 _superblockId) public view returns (bytes32) {
        return superblocks[_superblockId].parentId;
    }

    // @dev - Return superblock accumulated work
    function getSuperblockAccumulatedWork(bytes32 _superblockId) public view returns (uint) {
        return superblocks[_superblockId].accumulatedWork;
    }

    // @dev - Return superblock status
    function getSuperblockStatus(bytes32 _superblockId) public view returns (Status) {
        return superblocks[_superblockId].status;
    }

    // @dev - Return indexNextSuperblock
    function getIndexNextSuperblock() public view returns (uint32) {
        return indexNextSuperblock;
    }

    // @dev - Calculte merkle root from hashes
    function makeMerkle(bytes32[] hashes) public pure returns (bytes32) {
        return DogeTx.makeMerkle(hashes);
    }

    function isApproved(bytes32 _superblockId) public view returns (bool) {
        return (getSuperblockStatus(_superblockId) == Status.Approved);
    }

    function getChainHeight() public view returns (uint) {
        return superblocks[bestSuperblock].height;
    }

    // @dev - write `_fourBytes` into `_word` starting from `_position`
    // This is useful for writing 32bit ints inside one 32 byte word
    //
    // @param _word - information to be partially overwritten
    // @param _position - position to start writing from
    // @param _eightBytes - information to be written
    function writeUint32(bytes32 _word, uint _position, uint32 _fourBytes) private pure returns (bytes32) {
        bytes32 result;
        assembly {
            let pointer := mload(0x40)
            mstore(pointer, _word)
            mstore8(add(pointer, _position), byte(28, _fourBytes))
            mstore8(add(pointer, add(_position,1)), byte(29, _fourBytes))
            mstore8(add(pointer, add(_position,2)), byte(30, _fourBytes))
            mstore8(add(pointer, add(_position,3)), byte(31, _fourBytes))
            result := mload(pointer)
        }
        return result;
    }

    uint constant ANCESTOR_STEP = 5;
    uint constant NUM_ANCESTOR_DEPTHS = 8;

    // @dev - Update ancestor to the new height
    function updateAncestors(bytes32 ancestors, uint32 index, uint height) internal pure returns (bytes32) {
        uint step = ANCESTOR_STEP;
        ancestors = writeUint32(ancestors, 0, index);
        uint i = 1;
        while (i<NUM_ANCESTOR_DEPTHS && (height % step == 1)) {
            ancestors = writeUint32(ancestors, 4*i, index);
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
    function getSuperblockLocator() public view returns (bytes32[9]) {
        bytes32[9] memory locator;
        locator[0] = bestSuperblock;
        bytes32 ancestors = getSuperblockAncestors(bestSuperblock);
        uint i = NUM_ANCESTOR_DEPTHS;
        while (i > 0) {
            locator[i] = indexSuperblock[uint32(ancestors & 0xFFFFFFFF)];
            ancestors >>= 32;
            --i;
        }
        return locator;
    }
}

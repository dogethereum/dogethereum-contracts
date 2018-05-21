pragma solidity ^0.4.19;

import {DogeTx} from "./DogeParser/DogeTx.sol";
import {DogeRelay} from "./DogeRelay.sol";
import {SuperblockErrorCodes} from "./SuperblockErrorCodes.sol";


// @dev - Manages superblocks
//
// Management of superblocks and status transitions
contract Superblocks is SuperblockErrorCodes {

    // @dev - Superblock status
    enum Status { Unitialized, New, InBattle, SemiApproved, Approved, Invalid }

    struct SuperblockInfo {
        bytes32 blocksMerkleRoot;
        uint accumulatedWork;
        uint timestamp;
        bytes32 lastHash;
        bytes32 parentId;
        address submitter;
        bytes32 ancestors;
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

    // ClaimManager
    address public claimManager;

    // DogeRelay
    address public dogeRelay;

    modifier onlyClaimManager() {
        require(msg.sender == claimManager);
        _;
    }

    // @dev – the constructor
    constructor(DogeRelay _dogeRelay) public {
        dogeRelay = _dogeRelay;
    }

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
    // @param _lastHash Hash of the last block in the superblock
    // @param _parentId Id of the parent superblock
    // @return Error code and superblockId
    function initialize(bytes32 _blocksMerkleRoot, uint _accumulatedWork, uint _timestamp, bytes32 _lastHash, bytes32 _parentId) public returns (uint, bytes32) {
        require(bestSuperblock == 0);
        require(_parentId == 0);

        bytes32 superblockId = calcSuperblockId(_blocksMerkleRoot, _accumulatedWork, _timestamp, _lastHash, _parentId);
        SuperblockInfo storage superblock = superblocks[superblockId];

        require(superblock.status == Status.Unitialized);

        indexSuperblock[indexNextSuperblock] = superblockId;

        superblock.blocksMerkleRoot = _blocksMerkleRoot;
        superblock.accumulatedWork = _accumulatedWork;
        superblock.timestamp = _timestamp;
        superblock.lastHash = _lastHash;
        superblock.parentId = _parentId;
        superblock.submitter = msg.sender;
        superblock.index = indexNextSuperblock;
        superblock.height = 0;
        superblock.status = Status.Approved;
        superblock.ancestors = 0x0;

        indexNextSuperblock++;

        emit NewSuperblock(superblockId, msg.sender);

        bestSuperblock = superblockId;
        bestSuperblockaccumulatedWork = _accumulatedWork;

        emit ApprovedSuperblock(superblockId, msg.sender);

        return (SuperblockErrorCodes.ERR_SUPERBLOCK_OK, superblockId);
    }

    // @dev - Proposes a new superblock
    //
    // A new superblock to be accepted it has to have a parent superblock
    // approved or semi approved.
    //
    // @param _blocksMerkleRoot Root of the merkle tree of blocks contained in a superblock
    // @param _accumulatedWork Accumulated proof of work of the last block in the superblock
    // @param _timestamp Timestamp of the last block in the superblock
    // @param _lastHash Hash of the last block in the superblock
    // @param _parentId Id of the parent superblock
    // @return Error code and superblockId
    function propose(bytes32 _blocksMerkleRoot, uint _accumulatedWork, uint _timestamp, bytes32 _lastHash, bytes32 _parentId, address submitter) public returns (uint, bytes32) {
        if (msg.sender != claimManager) {
            emit ErrorSuperblock(0, ERR_SUPERBLOCK_NOT_CLAIMMANAGER);
            return (ERR_SUPERBLOCK_NOT_CLAIMMANAGER, 0);
        }

        SuperblockInfo storage parent = superblocks[_parentId];
        if (parent.status != Status.SemiApproved && parent.status != Status.Approved) {
            emit ErrorSuperblock(superblockId, ERR_SUPERBLOCK_BAD_PARENT);
            return (ERR_SUPERBLOCK_BAD_PARENT, 0);
        }

        bytes32 superblockId = calcSuperblockId(_blocksMerkleRoot, _accumulatedWork, _timestamp, _lastHash, _parentId);
        SuperblockInfo storage superblock = superblocks[superblockId];
        if (superblock.status != Status.Unitialized) {
            emit ErrorSuperblock(superblockId, ERR_SUPERBLOCK_EXIST);
            return (ERR_SUPERBLOCK_EXIST, 0);
        }

        indexSuperblock[indexNextSuperblock] = superblockId;

        superblock.blocksMerkleRoot = _blocksMerkleRoot;
        superblock.accumulatedWork = _accumulatedWork;
        superblock.timestamp = _timestamp;
        superblock.lastHash = _lastHash;
        superblock.parentId = _parentId;
        superblock.submitter = submitter;
        superblock.index = indexNextSuperblock;
        superblock.height = parent.height + 1;
        superblock.status = Status.New;
        superblock.ancestors = updateAncestors(parent.ancestors, parent.index, parent.height + 1);

        indexNextSuperblock++;

        emit NewSuperblock(superblockId, msg.sender);

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
    function confirm(bytes32 _superblockId) public returns (uint, bytes32) {
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
        emit ApprovedSuperblock(_superblockId, msg.sender);
        return (ERR_SUPERBLOCK_OK, _superblockId);
    }

    // @dev - Challenge a proposed superblock
    //
    // A new superblock can be challenged to start a battle
    // to verify the correctness of the data submitted.
    //
    // @param _superblockId Id of the superblock to challenge
    // @return Error code and superblockId
    function challenge(bytes32 _superblockId) public returns (uint, bytes32) {
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
        emit ChallengeSuperblock(_superblockId, msg.sender);
        return (ERR_SUPERBLOCK_OK, _superblockId);
    }

    // @dev - Semi-approve a challenged superblock
    //
    // A challenged superblock can be marked as semi-approved
    // if it satisfies all the queries or when all challengers has
    // stopped participating.
    //
    // @param _superblockId Id of the superblock to semi-approve
    // @return Error code and superblockId
    function semiApprove(bytes32 _superblockId) public returns (uint, bytes32) {
        if (msg.sender != claimManager) {
            emit ErrorSuperblock(_superblockId, ERR_SUPERBLOCK_NOT_CLAIMMANAGER);
            return (ERR_SUPERBLOCK_NOT_CLAIMMANAGER, 0);
        }
        SuperblockInfo storage superblock = superblocks[_superblockId];
        if (superblock.status != Status.InBattle) {
            emit ErrorSuperblock(_superblockId, ERR_SUPERBLOCK_BAD_STATUS);
            return (ERR_SUPERBLOCK_BAD_STATUS, 0);
        }
        superblock.status = Status.SemiApproved;
        emit SemiApprovedSuperblock(_superblockId, msg.sender);
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
    function invalidate(bytes32 _superblockId) public returns (uint, bytes32) {
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
        emit InvalidSuperblock(_superblockId, msg.sender);
        return (ERR_SUPERBLOCK_OK, _superblockId);
    }

    // @dev - Evaluate the SuperblockId
    //
    // Evaluate the SuperblockId given the superblock data.
    //
    // @param _blocksMerkleRoot Root of the merkle tree of blocks contained in a superblock
    // @param _accumulatedWork Accumulated proof of work of the last block in the superblock
    // @param _timestamp Timestamp of the last block in the superblock
    // @param _lastHash Hash of the last block in the superblock
    // @param _parentId Id of the parent superblock
    // @return Superblock id
    function calcSuperblockId(bytes32 _blocksMerkleRoot, uint _accumulatedWork, uint _timestamp, bytes32 _lastHash, bytes32 _parentId) public pure returns (bytes32) {
        return keccak256(_blocksMerkleRoot, _accumulatedWork, _timestamp, _lastHash, _parentId);
    }

    // @dev - Returns the superblock with the most accumulated work
    //
    // The confirmed superblock with most accumulated work.
    //
    // @return Superblock id
    function getBestSuperblock() public view returns (bytes32) {
        return bestSuperblock;
    }

    // @dev - Returns the superblock with the most accumulated work
    //
    // The confirmed superblock with most accumulated work.
    //
    // @return {
    //   bytes32 _blocksMerkleRoot,
    //   uint _accumulatedWork,
    //   uint _timestamp,
    //   bytes32 _lastHash,
    //   bytes32 _parentId,
    //   address _submitter,
    //   Status _status
    // }  Superblock data
    function getSuperblock(bytes32 superblockId) public view returns (
        bytes32 _blocksMerkleRoot,
        uint _accumulatedWork,
        uint _timestamp,
        bytes32 _lastHash,
        bytes32 _parentId,
        address _submitter,
        Status _status
    ) {
        SuperblockInfo storage superblock = superblocks[superblockId];
        return (
            superblock.blocksMerkleRoot,
            superblock.accumulatedWork,
            superblock.timestamp,
            superblock.lastHash,
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

    // @dev - Calculte merkle root from hashes
    function makeMerkle(bytes32[] hashes) public pure returns (bytes32) {
        return DogeTx.makeMerkle(hashes);
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

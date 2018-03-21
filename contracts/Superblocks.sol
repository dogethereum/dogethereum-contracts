pragma solidity ^0.4.19;

//FIXME: The access of most methods is public but should be internal

// @dev - Manages superblocks
//
// Management of superblocks and status transitions
contract Superblocks {

    uint constant SUPERBLOCK_PERIOD = 0;

    enum Status { Unitialized, New, InBattle, SemiApproved, Approved, Invalid }

    struct SuperblockInfo {
        bytes32 blocksMerkleRoot;
        uint accumulatedWork;
        uint timestamp;
        bytes32 lastHash;
        bytes32 parentId;
        address submitter;
        Status status;
    }

    // Mapping superblock id => superblock data
    mapping (bytes32 => SuperblockInfo) superblocks;

    bytes32 bestSuperblock;
    uint accumulatedWork;

    //TODO: Add 'indexed' to parameters
    event NewSuperblock(bytes32 superblockId, address who);
    event ApprovedSuperblock(bytes32 superblockId, address who);
    event ChallengeSuperblock(bytes32 superblockId, address who);
    event SemiApprovedSuperblock(bytes32 superblockId, address who);
    event InvalidSuperblock(bytes32 superblockId, address who);

    event ErrorSuperblock(bytes32 superblockId, uint err);

    // @dev – the constructor
    function Superblocks() public {
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
        require(accumulatedWork == 0);
        require(_parentId == 0);

        bytes32 superblockId = calcSuperblockId(_blocksMerkleRoot, _accumulatedWork, _timestamp, _lastHash, _parentId);
        SuperblockInfo storage superblock = superblocks[superblockId];

        require(superblock.status == Status.Unitialized);

        superblock.blocksMerkleRoot = _blocksMerkleRoot;
        superblock.accumulatedWork = _accumulatedWork;
        superblock.timestamp = _timestamp;
        superblock.lastHash = _lastHash;
        superblock.parentId = _parentId;
        superblock.submitter = msg.sender;
        superblock.status = Status.Approved;

        emit NewSuperblock(superblockId, msg.sender);

        bestSuperblock = superblockId;
        accumulatedWork = _accumulatedWork;

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
    // @param _lastHash Hash of the last block in the superblock
    // @param _parentId Id of the parent superblock
    // @return Error code and superblockId
    function propose(bytes32 _blocksMerkleRoot, uint _accumulatedWork, uint _timestamp, bytes32 _lastHash, bytes32 _parentId) public returns (uint, bytes32) {
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

        superblock.blocksMerkleRoot = _blocksMerkleRoot;
        superblock.accumulatedWork = _accumulatedWork;
        superblock.timestamp = _timestamp;
        superblock.lastHash = _lastHash;
        superblock.parentId = _parentId;
        superblock.submitter = msg.sender;
        superblock.status = Status.New;

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
        if (superblock.accumulatedWork > accumulatedWork) {
            bestSuperblock = _superblockId;
            accumulatedWork = superblock.accumulatedWork;
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
    function semiApprove(bytes32 _superblockId) public returns (uint) {
        SuperblockInfo storage superblock = superblocks[_superblockId];
        if (superblock.status != Status.InBattle) {
            emit ErrorSuperblock(_superblockId, ERR_SUPERBLOCK_BAD_STATUS);
            return ERR_SUPERBLOCK_BAD_STATUS;
        }
        superblock.status = Status.SemiApproved;
        emit SemiApprovedSuperblock(_superblockId, msg.sender);
        return ERR_SUPERBLOCK_OK;
    }

    // @dev - Invalidates a superblock
    //
    // A superblock with incorrect data can be invalidated immediately.
    // Superblocks that are not in the main chain can be invalidates
    // if not enough superblocks follows them.
    //
    // @param _superblockId Id of the superblock to invalidate
    // @return Error code and superblockId
    function invalidate(bytes32 _superblockId) public returns (uint) {
        SuperblockInfo storage superblock = superblocks[_superblockId];
        if (superblock.status != Status.InBattle && superblock.status != Status.SemiApproved) {
            emit ErrorSuperblock(_superblockId, ERR_SUPERBLOCK_BAD_STATUS);
            return ERR_SUPERBLOCK_BAD_STATUS;
        }
        superblock.status = Status.Invalid;
        emit InvalidSuperblock(_superblockId, msg.sender);
        return ERR_SUPERBLOCK_OK;
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

    // @dev - Evaluate the merkle root
    //
    // Given an array of hashes it calculates the
    // root of the merkle tree.
    //
    // @return root of merkle tree
    function makeMerkle(bytes32[] hashes) public pure returns (bytes32) {
        uint length = hashes.length;
        if (length == 0) return sha256();
        uint i;
        uint j;
        uint k;
        while (length > 1) {
            k = 0;
            for (i = 0; i < length; i += 2) {
                j = i+1<length ? i+1 : length-1;
                hashes[k] = sha256(hashes[i], hashes[j]);
                k += 1;
            }
            length = k;
        }
        return hashes[0];
    }

    // Error codes
    uint constant ERR_SUPERBLOCK_OK = 0;
    uint constant ERR_SUPERBLOCK_EXIST = 50010;
    uint constant ERR_SUPERBLOCK_BAD_STATUS = 50020;
    uint constant ERR_SUPERBLOCK_TIMEOUT = 50030;
    uint constant ERR_SUPERBLOCK_INVALID_MERKLE = 50040;
    uint constant ERR_SUPERBLOCK_BAD_PARENT = 50050;

    uint constant ERR_SUPERBLOCK_MIN_DEPOSIT = 50060;
}

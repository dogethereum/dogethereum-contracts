pragma solidity ^0.4.19;

import {DogeErrorCodes} from "./DogeErrorCodes.sol";
import {DogeSuperblocks} from './DogeSuperblocks.sol';
import {DogeTx} from './DogeParser/DogeTx.sol';
import {IScryptCheckerListener} from "./IScryptCheckerListener.sol";

// @dev - Manages a battle session between superblock submitter and challenger
contract DogeBattleManager is DogeErrorCodes {

    enum Network { MAINNET, TESTNET, REGTEST }

    enum ChallengeState {
        Unchallenged,             // Unchallenged submission
        Challenged,               // Claims was challenged
        QueryMerkleRootHashes,    // Challenger expecting block hashes
        RespondMerkleRootHashes,  // Blcok hashes were received and verified
        QueryBlockHeader,         // Challenger is requesting block headers
        RespondBlockHeader,       // All block headers were received
        VerifyScryptHash,
        PendingVerification,      // Pending superblock verification
        SuperblockVerified,       // Superblock verified
        SuperblockFailed          // Superblock not valid
    }

    enum BlockInfoStatus {
        Uninitialized,
        Requested,
        ScryptHashPending,
        ScryptHashVerified,
        ScryptHashFailed
    }

    struct BlockInfo {
        bytes32 prevBlock;
        uint64 timestamp;
        uint32 bits;
        BlockInfoStatus status;
    }

    struct BattleSession {
        bytes32 id;
        bytes32 superblockId;
        address submitter;
        address challenger;
        uint lastActionTimestamp;         // Last action timestamp
        uint lastActionClaimant;          // Number last action submitter
        uint lastActionChallenger;        // Number last action challenger
        uint actionsCounter;              // Counter session actions

        bytes32[] blockHashes;                      // Block hashes
        uint countBlockHeaderQueries;               // Number of block header queries
        uint countBlockHeaderResponses;             // Number of block header responses

        mapping(bytes32 => BlockInfo) blockInfos;

        bytes32 pendingScryptHashId;

        ChallengeState challengeState;              // Claim state
    }

    struct ScryptHashVerification {
        bytes32 sessionId;
        bytes32 blockSha256Hash;
    }

    mapping(bytes32 => BattleSession) public sessions;

    uint public sessionsCount = 0;

    uint public superblockDuration;         // Superblock duration (in seconds)
    uint public superblockDelay;            // Delay required to submit superblocks (in seconds)
    uint public superblockTimeout;          // Timeout action (in seconds)

    // Verifications
    uint public numScryptHashVerifications;

    mapping (bytes32 => ScryptHashVerification) public scryptHashVerifications;

    // network that the stored blocks belong to
    Network private net;

    event NewBattle(bytes32 sessionId, address submitter, address challenger);
    event ChallengerConvicted(bytes32 sessionId, address challenger);
    event SubmitterConvicted(bytes32 sessionId, address submitter);

    event QueryMerkleRootHashes(bytes32 sessionId, address submitter);
    event RespondMerkleRootHashes(bytes32 sessionId, address challenger, bytes32[] blockHashes);
    event QueryBlockHeader(bytes32 sessionId, address submitter, bytes32 blockHash);
    event RespondBlockHeader(bytes32 sessionId, address challenger, bytes32 blockScryptHash, bytes blockHeader);

    event ErrorBattle(bytes32 sessionId, uint err);

    modifier onlyFrom(address sender) {
        require(msg.sender == sender);
        _;
    }

    modifier onlyClaimant(bytes32 sessionId) {
        require(msg.sender == sessions[sessionId].submitter);
        _;
    }

    modifier onlyChallenger(bytes32 sessionId) {
        require(msg.sender == sessions[sessionId].challenger);
        _;
    }

    constructor(Network _network, uint _superblockDuration, uint _superblockDelay, uint _superblockTimeout) public {
        net = _network;
        superblockDuration = _superblockDuration;
        superblockDelay = _superblockDelay;
        superblockTimeout = _superblockTimeout;
    }

    // @dev - Start a battle session
    function beginBattleSession(bytes32 superblockId, address submitter, address challenger) public returns (bytes32) {
        bytes32 sessionId = keccak256(abi.encode(superblockId, msg.sender, sessionsCount));
        BattleSession storage session = sessions[sessionId];
        session.id = sessionId;
        session.superblockId = superblockId;
        session.submitter = submitter;
        session.challenger = challenger;
        session.lastActionTimestamp = block.timestamp;
        session.lastActionChallenger = 0;
        session.lastActionClaimant = 1;     // Force challenger to start
        session.actionsCounter = 1;
        session.challengeState = ChallengeState.Challenged;

        sessionsCount += 1;

        emit NewBattle(sessionId, submitter, challenger);
        return sessionId;
    }

    // @dev - Challenger makes a query for superblock hashes
    function doQueryMerkleRootHashes(bytes32 sessionId) internal returns (bool) {
        BattleSession storage session = sessions[sessionId];
        if (session.challengeState == ChallengeState.Challenged) {
            session.challengeState = ChallengeState.QueryMerkleRootHashes;
            return true;
        }
        return false;
    }

    // @dev - Challenger makes a query for superblock hashes
    function queryMerkleRootHashes(bytes32 sessionId) onlyChallenger(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        bool succeeded = false;
        succeeded = doQueryMerkleRootHashes(sessionId);
        if (succeeded) {
            session.actionsCounter += 1;
            session.lastActionTimestamp = block.timestamp;
            session.lastActionChallenger = session.actionsCounter;
            emit QueryMerkleRootHashes(sessionId, session.submitter);
        }
    }

    // @dev - Submitter send hashes to verify superblock merkle root
    function doVerifyMerkleRootHashes(bytes32 sessionId, bytes32[] blockHashes) internal returns (bool) {
        BattleSession storage session = sessions[sessionId];
        require(session.blockHashes.length == 0);
        if (session.challengeState == ChallengeState.QueryMerkleRootHashes) {
            bytes32 merkleRoot;
            bytes32 lastHash;
            (merkleRoot, , , lastHash, , , ) = getSuperblockInfo(session.superblockId);
            require(lastHash == blockHashes[blockHashes.length - 1]);
            require(merkleRoot == DogeTx.makeMerkle(blockHashes));
            session.blockHashes = blockHashes;
            session.challengeState = ChallengeState.RespondMerkleRootHashes;
            return true;
        }
        return false;
    }

    // @dev - For the submitter to respond to challenger queries
    function respondMerkleRootHashes(bytes32 sessionId, bytes32[] blockHashes) onlyClaimant(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        bool succeeded = false;
        succeeded = doVerifyMerkleRootHashes(sessionId, blockHashes);
        if (succeeded) {
            session.actionsCounter += 1;
            session.lastActionTimestamp = block.timestamp;
            session.lastActionClaimant = session.actionsCounter;
            emit RespondMerkleRootHashes(sessionId, session.challenger, blockHashes);
        }
    }

    function confirmScryptHashVerification(BattleSession storage session) internal {
        require(session.pendingScryptHashId != 0x0);
        bytes32 pendingScryptHashId = session.pendingScryptHashId;
        ScryptHashVerification storage verification = scryptHashVerifications[pendingScryptHashId];
        require(verification.sessionId != 0x0);
        notifyScryptHashSucceeded(verification.sessionId, verification.blockSha256Hash);
        delete scryptHashVerifications[pendingScryptHashId];
        session.pendingScryptHashId = 0x0;
    }

    // @dev - Challenger makes a query for block header data for a hash
    function doQueryBlockHeader(bytes32 sessionId, bytes32 blockHash) internal returns (bool) {
        BattleSession storage session = sessions[sessionId];
        if (session.challengeState == ChallengeState.VerifyScryptHash) {
            confirmScryptHashVerification(session);
        }
        if ((session.countBlockHeaderQueries == 0 && session.challengeState == ChallengeState.RespondMerkleRootHashes) ||
            (session.countBlockHeaderQueries > 0 && session.challengeState == ChallengeState.RespondBlockHeader)) {
            require(session.countBlockHeaderQueries < session.blockHashes.length);
            require(session.blockInfos[blockHash].status == BlockInfoStatus.Uninitialized);
            session.countBlockHeaderQueries += 1;
            session.blockInfos[blockHash].status = BlockInfoStatus.Requested;
            session.challengeState = ChallengeState.QueryBlockHeader;
            return true;
        }
        return false;
    }

    // @dev - For the challenger to start a query
    function queryBlockHeader(bytes32 sessionId, bytes32 blockHash) onlyChallenger(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        bool succeeded = false;
        succeeded = doQueryBlockHeader(sessionId, blockHash);
        if (succeeded) {
            session.actionsCounter += 1;
            session.lastActionTimestamp = block.timestamp;
            session.lastActionChallenger = session.actionsCounter;
            emit QueryBlockHeader(sessionId, session.submitter, blockHash);
        }
    }

    function verifyTimestamp(bytes32 superblockId, bytes blockHeader) internal view returns (bool) {
        uint blockTimestamp = DogeTx.getTimestamp(blockHeader, 0);
        uint superblockTimestamp;

        (, , superblockTimestamp, , , , ) = getSuperblockInfo(superblockId);

        // Block timestamp to be within the expected timestamp of the superblock
        return (blockTimestamp / superblockDuration <= superblockTimestamp / superblockDuration)
            && (blockTimestamp / superblockDuration >= superblockTimestamp / superblockDuration - 1);
    }

    // @dev - Verify block header send by challenger
    function doVerifyBlockHeader(bytes32 sessionId, bytes32 blockScryptHash, bytes blockHeader) internal returns (bool) {
        BattleSession storage session = sessions[sessionId];
        if (session.challengeState == ChallengeState.QueryBlockHeader) {
            bytes32 blockSha256Hash = bytes32(DogeTx.dblShaFlipMem(blockHeader, 0, 80));
            require(session.blockInfos[blockSha256Hash].status == BlockInfoStatus.Requested);

            require(verifyTimestamp(session.superblockId, blockHeader));

            uint err;
            uint blockHash;
            uint scryptHash;
            bool mergeMined;
            (err, blockHash, scryptHash, mergeMined) = DogeTx.verifyBlockHeader(blockHeader, 0, blockHeader.length, uint(blockScryptHash));
            require(err == 0);

            bytes32 pendingScryptHashId = doVerifyScryptHash(sessionId, blockSha256Hash, bytes32(scryptHash), blockHeader, mergeMined, session.submitter);

            session.blockInfos[blockSha256Hash].status = BlockInfoStatus.ScryptHashPending;
            session.blockInfos[blockSha256Hash].timestamp = DogeTx.getTimestamp(blockHeader, 0);
            session.blockInfos[blockSha256Hash].bits = DogeTx.getBits(blockHeader, 0);
            session.blockInfos[blockSha256Hash].prevBlock = bytes32(DogeTx.getHashPrevBlock(blockHeader, 0));

            session.countBlockHeaderResponses += 1;
            session.challengeState = ChallengeState.VerifyScryptHash;
            session.pendingScryptHashId = pendingScryptHashId;
            return true;
        }
        return false;
    }

    // @dev - For the submitter to respond to challenger queries
    function respondBlockHeader(bytes32 sessionId, bytes32 blockScryptHash, bytes blockHeader) onlyClaimant(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        bool succeeded = false;
        succeeded = doVerifyBlockHeader(sessionId, blockScryptHash, blockHeader);
        if (succeeded) {
            session.actionsCounter += 1;
            session.lastActionTimestamp = block.timestamp;
            session.lastActionClaimant = session.actionsCounter;
            emit RespondBlockHeader(sessionId, session.challenger, blockScryptHash, blockHeader);
        }
    }

    function validateProofOfWork(BattleSession storage session) internal view returns (uint) {
        uint accWork;
        uint parentWork;
        bytes32 parentId;
        bytes32 prevBlock;
        uint timestamp;
        uint prevTimestamp;
        uint32 prevBits;
        (, accWork, , , parentId, , ) = getSuperblockInfo(session.superblockId);
        (, parentWork, timestamp, prevBlock, , , ) = getSuperblockInfo(parentId);
        uint idx = 0;
        uint work;
        while (idx < session.blockHashes.length) {
            bytes32 blockSha256Hash = session.blockHashes[idx];
            uint32 bits = session.blockInfos[blockSha256Hash].bits;
            if (session.blockInfos[blockSha256Hash].prevBlock != prevBlock) {
                return ERR_SUPERBLOCK_BAD_PARENT;
            }
            if (idx > 0) {
                uint32 newBits = DogeTx.calculateDigishieldDifficulty(int64(timestamp) - int64(prevTimestamp), prevBits);
                if (net == Network.TESTNET && session.blockInfos[blockSha256Hash].timestamp - timestamp > 120) {
                    newBits = 0x1e0fffff;
                }
                if (bits != newBits) {
                    return ERR_SUPERBLOCK_BAD_BITS;
                }
            }
            work += DogeTx.diffFromBits(session.blockInfos[blockSha256Hash].bits);
            prevBlock = blockSha256Hash;
            prevBits = session.blockInfos[blockSha256Hash].bits;
            prevTimestamp = timestamp;
            timestamp = session.blockInfos[blockSha256Hash].timestamp;
            idx += 1;
        }
        if (parentWork + work != accWork) {
            return ERR_SUPERBLOCK_BAD_ACCUMULATED_WORK;
        }
        return ERR_SUPERBLOCK_OK;
    }

    // @dev - Verify a superblock data is consistent
    // Only should be called when all blocks header were submitted
    function doVerifySuperblock(bytes32 sessionId) internal returns (uint) {
        BattleSession storage session = sessions[sessionId];
        if (session.challengeState == ChallengeState.VerifyScryptHash) {
            confirmScryptHashVerification(session);
        }
        if (session.challengeState == ChallengeState.PendingVerification) {
            uint err = validateProofOfWork(session);
            if (err != 0) {
                emit ErrorBattle(sessionId, err);
                return 2;
            }
            return 1;
        } else if (session.challengeState == ChallengeState.SuperblockFailed) {
            return 2;
        }
        return 0;
    }

    // @dev - Perform final verification once all blocks were submitted
    function verifySuperblock(bytes32 sessionId) public {
        BattleSession storage session = sessions[sessionId];
        uint status = doVerifySuperblock(sessionId);
        if (status == 1) {
            convictChallenger(sessionId, session.challenger, session.superblockId);
        } else if (status == 2) {
            convictSubmitter(sessionId, session.submitter, session.superblockId);
        }
    }

    // @dev - Able to trigger conviction if time of response is too high
    function timeout(bytes32 sessionId) public returns (uint) {
        BattleSession storage session = sessions[sessionId];
        if (session.lastActionChallenger > session.lastActionClaimant &&
            block.timestamp > session.lastActionTimestamp + superblockTimeout) {
            convictSubmitter(sessionId, session.submitter, session.superblockId);
            return ERR_SUPERBLOCK_OK;
        } else if (session.lastActionClaimant > session.lastActionChallenger &&
            block.timestamp > session.lastActionTimestamp + superblockTimeout) {
            convictChallenger(sessionId, session.challenger, session.superblockId);
            return ERR_SUPERBLOCK_OK;
        } else {
            emit ErrorBattle(sessionId, ERR_SUPERBLOCK_NO_TIMEOUT);
            return ERR_SUPERBLOCK_NO_TIMEOUT;
        }
    }

    // @dev - To be called when a challenger is convicted
    function convictChallenger(bytes32 sessionId, address challenger, bytes32 superblockId) internal {
        BattleSession storage session = sessions[sessionId];
        sessionDecided(sessionId, superblockId, session.submitter, session.challenger);
        disable(sessionId);
        emit ChallengerConvicted(sessionId, challenger);
    }

    // @dev - To be called when a submitter is convicted
    function convictSubmitter(bytes32 sessionId, address submitter, bytes32 superblockId) internal {
        BattleSession storage session = sessions[sessionId];
        sessionDecided(sessionId, superblockId, session.challenger, session.submitter);
        disable(sessionId);
        emit SubmitterConvicted(sessionId, submitter);
    }

    // @dev - Disable session
    // It should be called only when either the submitter or the challenger were convicted.
    function disable(bytes32 sessionId) internal {
        delete sessions[sessionId];
    }

    // @dev Scrypt verification succeeded
    function notifyScryptHashSucceeded(bytes32 sessionId, bytes32 blockSha256Hash) internal {
        BattleSession storage session = sessions[sessionId];
        if (session.challengeState == ChallengeState.VerifyScryptHash) {
            require(session.blockInfos[blockSha256Hash].status == BlockInfoStatus.ScryptHashPending);
            session.blockInfos[blockSha256Hash].status = BlockInfoStatus.ScryptHashVerified;
            if (session.countBlockHeaderResponses == session.blockHashes.length) {
                session.challengeState = ChallengeState.PendingVerification;
            } else {
                session.challengeState = ChallengeState.RespondBlockHeader;
            }
        }
    }

    // @dev Scrypt verification failed
    function notifyScryptHashFailed(bytes32 sessionId, bytes32 blockSha256Hash) internal {
        BattleSession storage session = sessions[sessionId];
        if (session.challengeState == ChallengeState.VerifyScryptHash) {
            require(session.blockInfos[blockSha256Hash].status == BlockInfoStatus.ScryptHashPending);
            session.blockInfos[blockSha256Hash].status = BlockInfoStatus.ScryptHashFailed;
            session.challengeState = ChallengeState.SuperblockFailed;
        }
    }

    // @dev - To be called when a battle sessions  was decided
    function sessionDecided(bytes32 sessionId, bytes32 superblockId, address winner, address loser) internal;

    // @dev - To verify block header scrypt hash
    function doVerifyScryptHash(bytes32 sessionId, bytes32 blockScryptHash, bytes32 blockHash, bytes blockHeader, bool isMergeMined, address submitter) internal returns (bytes32);

    // @dev - Retrieve superblock information
    function getSuperblockInfo(bytes32 superblockId) internal view returns (
        bytes32 _blocksMerkleRoot,
        uint _accumulatedWork,
        uint _timestamp,
        bytes32 _lastHash,
        bytes32 _parentId,
        address _submitter,
        DogeSuperblocks.Status _status
    );
}

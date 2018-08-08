pragma solidity ^0.4.19;

import {DogeErrorCodes} from "./DogeErrorCodes.sol";
import {DogeSuperblocks} from './DogeSuperblocks.sol';
import {DogeTx} from './DogeParser/DogeTx.sol';
import {IScryptChecker} from "./IScryptChecker.sol";
import {IScryptCheckerListener} from "./IScryptCheckerListener.sol";

// @dev - Manages a battle session between superblock submitter and challenger
contract DogeBattleManager is DogeErrorCodes, IScryptCheckerListener {

    enum Network { MAINNET, TESTNET, REGTEST }

    enum ChallengeState {
        Unchallenged,             // Unchallenged submission
        Challenged,               // Claims was challenged
        QueryMerkleRootHashes,    // Challenger expecting block hashes
        RespondMerkleRootHashes,  // Blcok hashes were received and verified
        QueryBlockHeader,         // Challenger is requesting block headers
        RespondBlockHeader,       // All block headers were received
        VerifyScryptHash,
        RequestScryptVerification,
        PendingScryptVerification,
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
        bytes powBlockHeader;
        bytes32 scryptHash;
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

        mapping(bytes32 => BlockInfo) blocksInfo;

        bytes32 pendingScryptHashId;

        ChallengeState challengeState;              // Claim state
    }

    struct ScryptHashVerification {
        bytes32 sessionId;
        bytes32 blockSha256Hash;
    }

    uint public minDeposit = 1;

    mapping(bytes32 => BattleSession) public sessions;

    uint public sessionsCount = 0;

    uint public superblockDuration;         // Superblock duration (in seconds)
    uint public superblockDelay;            // Delay required to submit superblocks (in seconds)
    uint public superblockTimeout;          // Timeout action (in seconds)

    // Pending Scrypt Hash verifications
    uint public numScryptHashVerifications;

    mapping (bytes32 => ScryptHashVerification) public scryptHashVerifications;

    // network that the stored blocks belong to
    Network private net;

    // ScryptHash checker
    IScryptChecker public scryptChecker;

    event NewBattle(bytes32 superblockId, bytes32 sessionId, address submitter, address challenger);
    event ChallengerConvicted(bytes32 superblockId, bytes32 sessionId, address challenger);
    event SubmitterConvicted(bytes32 superblockId, bytes32 sessionId, address submitter);

    event QueryMerkleRootHashes(bytes32 superblockId, bytes32 sessionId, address submitter);
    event RespondMerkleRootHashes(bytes32 superblockId, bytes32 sessionId, address challenger, bytes32[] blockHashes);
    event QueryBlockHeader(bytes32 superblockId, bytes32 sessionId, address submitter, bytes32 blockHash);
    event RespondBlockHeader(bytes32 superblockId, bytes32 sessionId, address challenger, bytes32 blockScryptHash, bytes blockHeader, bytes powBlockHeader);
    event RequestScryptHashValidation(bytes32 superblockId, bytes32 sessionId, bytes32 blockScryptHash, bytes blockHeader, bytes32 proposalId, address submitter);
    event ResolveScryptHashValidation(bytes32 superblockId, bytes32 sessionId, bytes32 blockScryptHash, bytes32 proposalId, address challenger, bool valid);

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

    // @dev - sets ScryptChecker instance associated with this DogeClaimManager contract.
    // Once scryptChecker has been set, it cannot be changed.
    // An address of 0x0 means scryptChecker hasn't been set yet.
    //
    // @param _scryptChecker - address of the ScryptChecker contract to be associated with DogeClaimManager
    function setScryptChecker(address _scryptChecker) public {
        require(address(scryptChecker) == 0x0 && _scryptChecker != 0x0);
        scryptChecker = IScryptChecker(_scryptChecker);
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

        emit NewBattle(superblockId, sessionId, submitter, challenger);
        return sessionId;
    }

    // @dev - Challenger makes a query for superblock hashes
    function doQueryMerkleRootHashes(BattleSession storage session) internal returns (uint) {
        if (getDepositInternal(msg.sender) < minDeposit) {
            return ERR_SUPERBLOCK_MIN_DEPOSIT;
        }
        if (session.challengeState == ChallengeState.Challenged) {
            session.challengeState = ChallengeState.QueryMerkleRootHashes;
            assert(msg.sender == session.challenger);
            (uint err, ) = bondDeposit(session.superblockId, msg.sender, minDeposit);
            if (err != ERR_SUPERBLOCK_OK) {
                return err;
            }
            return ERR_SUPERBLOCK_OK;
        }
        return ERR_SUPERBLOCK_BAD_STATUS;
    }

    // @dev - Challenger makes a query for superblock hashes
    function queryMerkleRootHashes(bytes32 superblockId, bytes32 sessionId) onlyChallenger(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        uint err = doQueryMerkleRootHashes(session);
        if (err != ERR_SUPERBLOCK_OK) {
            emit ErrorBattle(sessionId, err);
        } else {
            session.actionsCounter += 1;
            session.lastActionTimestamp = block.timestamp;
            session.lastActionChallenger = session.actionsCounter;
            emit QueryMerkleRootHashes(superblockId, sessionId, session.submitter);
        }
    }

    // @dev - Submitter send hashes to verify superblock merkle root
    function doVerifyMerkleRootHashes(BattleSession storage session, bytes32[] blockHashes) internal returns (uint) {
        if (getDepositInternal(msg.sender) < minDeposit) {
            return ERR_SUPERBLOCK_MIN_DEPOSIT;
        }
        require(session.blockHashes.length == 0);
        if (session.challengeState == ChallengeState.QueryMerkleRootHashes) {
            (bytes32 merkleRoot, , , , bytes32 lastHash, , , , ) = getSuperblockInfo(session.superblockId);
            if (lastHash != blockHashes[blockHashes.length - 1]){
                return ERR_SUPERBLOCK_BAD_LASTBLOCK;
            }
            if (merkleRoot != DogeTx.makeMerkle(blockHashes)) {
                return ERR_SUPERBLOCK_INVALID_MERKLE;
            }
            (uint err, ) = bondDeposit(session.superblockId, msg.sender, minDeposit);
            if (err != ERR_SUPERBLOCK_OK) {
                return err;
            }
            session.blockHashes = blockHashes;
            session.challengeState = ChallengeState.RespondMerkleRootHashes;
            return ERR_SUPERBLOCK_OK;
        }
        return ERR_SUPERBLOCK_BAD_STATUS;
    }

    // @dev - For the submitter to respond to challenger queries
    function respondMerkleRootHashes(bytes32 superblockId, bytes32 sessionId, bytes32[] blockHashes) onlyClaimant(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        uint err = doVerifyMerkleRootHashes(session, blockHashes);
        if (err != 0) {
            emit ErrorBattle(sessionId, err);
        } else {
            session.actionsCounter += 1;
            session.lastActionTimestamp = block.timestamp;
            session.lastActionClaimant = session.actionsCounter;
            emit RespondMerkleRootHashes(superblockId, sessionId, session.challenger, blockHashes);
        }
    }

    // @dev - Challenger makes a query for block header data for a hash
    function doQueryBlockHeader(BattleSession storage session, bytes32 blockHash) internal returns (uint) {
        if (getDepositInternal(msg.sender) < minDeposit) {
            return ERR_SUPERBLOCK_MIN_DEPOSIT;
        }
        if (session.challengeState == ChallengeState.VerifyScryptHash) {
            skipScryptHashVerification(session);
        }
        if ((session.countBlockHeaderQueries == 0 && session.challengeState == ChallengeState.RespondMerkleRootHashes) ||
            (session.countBlockHeaderQueries > 0 && session.challengeState == ChallengeState.RespondBlockHeader)) {
            require(session.countBlockHeaderQueries < session.blockHashes.length);
            require(session.blocksInfo[blockHash].status == BlockInfoStatus.Uninitialized);
            (uint err, ) = bondDeposit(session.superblockId, msg.sender, minDeposit);
            if (err != ERR_SUPERBLOCK_OK) {
                return err;
            }
            session.countBlockHeaderQueries += 1;
            session.blocksInfo[blockHash].status = BlockInfoStatus.Requested;
            session.challengeState = ChallengeState.QueryBlockHeader;
            return ERR_SUPERBLOCK_OK;
        }
        return ERR_SUPERBLOCK_BAD_STATUS;
    }

    // @dev - For the challenger to start a query
    function queryBlockHeader(bytes32 superblockId, bytes32 sessionId, bytes32 blockHash) onlyChallenger(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        uint err = doQueryBlockHeader(session, blockHash);
        if (err != ERR_SUPERBLOCK_OK) {
            emit ErrorBattle(sessionId, err);
        } else {
            session.actionsCounter += 1;
            session.lastActionTimestamp = block.timestamp;
            session.lastActionChallenger = session.actionsCounter;
            emit QueryBlockHeader(superblockId, sessionId, session.submitter, blockHash);
        }
    }

    function verifyTimestamp(bytes32 superblockId, bytes blockHeader) internal view returns (bool) {
        uint blockTimestamp = DogeTx.getTimestamp(blockHeader, 0);
        uint superblockTimestamp;

        (, , superblockTimestamp, , , , , , ) = getSuperblockInfo(superblockId);

        // Block timestamp to be within the expected timestamp of the superblock
        return (blockTimestamp / superblockDuration <= superblockTimestamp / superblockDuration)
            && (blockTimestamp / superblockDuration >= superblockTimestamp / superblockDuration - 1);
    }

    // @dev - Generate request to verify block header scrypt hash
    function doVerifyScryptHash(bytes32 sessionId, bytes32 blockScryptHash, bytes32 blockSha256Hash, address submitter) internal returns (bytes32) {
        numScryptHashVerifications += 1;
        bytes32 proposalId = keccak256(abi.encodePacked(blockScryptHash, submitter, numScryptHashVerifications));

        scryptHashVerifications[proposalId] = ScryptHashVerification({
            sessionId: sessionId,
            blockSha256Hash: blockSha256Hash
        });

        return proposalId;
    }

    //
    function verifyBlockAuxPoW(BlockInfo storage blockInfo, bytes32 proposedBlockScryptHash, bytes blockHeader) internal returns (uint, bytes) {
        (uint err, , uint blockScryptHash, bool isMergeMined) = DogeTx.verifyBlockHeader(blockHeader, 0, blockHeader.length, uint(proposedBlockScryptHash));
        if (err != 0) {
            return (err, new bytes(0));
        }
        bytes memory powBlockHeader = (isMergeMined) ? DogeTx.sliceArray(blockHeader, blockHeader.length - 80, blockHeader.length) : DogeTx.sliceArray(blockHeader, 0, 80);
        blockInfo.timestamp = DogeTx.getTimestamp(blockHeader, 0);
        blockInfo.bits = DogeTx.getBits(blockHeader, 0);
        blockInfo.prevBlock = bytes32(DogeTx.getHashPrevBlock(blockHeader, 0));
        blockInfo.scryptHash = bytes32(blockScryptHash);
        blockInfo.powBlockHeader = powBlockHeader;
        return (ERR_SUPERBLOCK_OK, powBlockHeader);
    }

    // @dev - Verify block header send by challenger
    function doVerifyBlockHeader(BattleSession storage session, bytes32 sessionId, bytes32 proposedBlockScryptHash, bytes blockHeader) internal returns (uint, bytes) {
        if (getDepositInternal(msg.sender) < minDeposit) {
            return (ERR_SUPERBLOCK_MIN_DEPOSIT, new bytes(0));
        }
        if (session.challengeState == ChallengeState.QueryBlockHeader) {
            bytes32 blockSha256Hash = bytes32(DogeTx.dblShaFlipMem(blockHeader, 0, 80));
            BlockInfo storage blockInfo = session.blocksInfo[blockSha256Hash];
            if (blockInfo.status != BlockInfoStatus.Requested) {
                return (ERR_SUPERBLOCK_BAD_STATUS, new bytes(0));
            }

            if (!verifyTimestamp(session.superblockId, blockHeader)) {
                return (ERR_SUPERBLOCK_BAD_TIMESTAMP, new bytes(0));
            }

            (uint err, bytes memory powBlockHeader) = verifyBlockAuxPoW(blockInfo, proposedBlockScryptHash, blockHeader);
            if (err != ERR_SUPERBLOCK_OK) {
                return (err, new bytes(0));
            }

            blockInfo.status = BlockInfoStatus.ScryptHashPending;

            (err, ) = bondDeposit(session.superblockId, msg.sender, minDeposit);
            if (err != ERR_SUPERBLOCK_OK) {
                return (err, new bytes(0));
            }

            bytes32 pendingScryptHashId = doVerifyScryptHash(
                sessionId,
                blockInfo.scryptHash,
                blockSha256Hash,
                session.submitter
            );

            session.countBlockHeaderResponses += 1;
            session.challengeState = ChallengeState.VerifyScryptHash;
            session.pendingScryptHashId = pendingScryptHashId;

            return (ERR_SUPERBLOCK_OK, powBlockHeader);
        }
        return (ERR_SUPERBLOCK_BAD_STATUS, new bytes(0));
    }

    // @dev - For the submitter to respond to challenger queries
    function respondBlockHeader(bytes32 superblockId, bytes32 sessionId, bytes32 blockScryptHash, bytes blockHeader) onlyClaimant(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        (uint err, bytes memory powBlockHeader) = doVerifyBlockHeader(session, sessionId, blockScryptHash, blockHeader);
        if (err != 0) {
            emit ErrorBattle(sessionId, err);
        } else {
            session.actionsCounter += 1;
            session.lastActionTimestamp = block.timestamp;
            session.lastActionClaimant = session.actionsCounter;
            emit RespondBlockHeader(superblockId, sessionId, session.challenger, blockScryptHash, blockHeader, powBlockHeader);
        }
    }

    function doRequestScryptHashValidation(BattleSession storage session, bytes32 superblockId, bytes32 sessionId, bytes32 blockSha256Hash) internal returns (uint) {
        if (getDepositInternal(msg.sender) < minDeposit) {
            return ERR_SUPERBLOCK_MIN_DEPOSIT;
        }
        if (session.challengeState == ChallengeState.VerifyScryptHash) {
            BlockInfo storage blockInfo = session.blocksInfo[blockSha256Hash];
            if (blockInfo.status == BlockInfoStatus.ScryptHashPending) {
                (uint err, ) = bondDeposit(session.superblockId, msg.sender, minDeposit);
                if (err != ERR_SUPERBLOCK_OK) {
                    return err;
                }
                emit RequestScryptHashValidation(superblockId, sessionId, blockInfo.scryptHash, blockInfo.powBlockHeader, session.pendingScryptHashId, session.submitter);
                session.challengeState = ChallengeState.RequestScryptVerification;
                return ERR_SUPERBLOCK_OK;
            }
        }
        return ERR_SUPERBLOCK_BAD_STATUS;
    }

    function requestScryptHashValidation(bytes32 superblockId, bytes32 sessionId, bytes32 blockSha256Hash) public onlyChallenger(sessionId) {
        BattleSession storage session = sessions[sessionId];
        uint err = doRequestScryptHashValidation(session, superblockId, sessionId, blockSha256Hash);
        if (err != 0) {
            emit ErrorBattle(sessionId, err);
        } else {
            session.actionsCounter += 1;
            session.lastActionTimestamp = block.timestamp;
            session.lastActionChallenger = session.actionsCounter;
        }
    }

    // Validate superblock information from last blocks
    function validateLastBlocks(BattleSession storage session) internal view returns (uint) {
        if (session.blockHashes.length <= 0) {
            return ERR_SUPERBLOCK_BAD_LASTBLOCK;
        }
        uint lastTimestamp;
        uint prevTimestamp;
        uint32 lastBits;
        bytes32 parentId;
        (, , lastTimestamp, prevTimestamp, , lastBits, parentId, , ) = getSuperblockInfo(session.superblockId);
        bytes32 blockSha256Hash = session.blockHashes[session.blockHashes.length - 1];
        if (session.blocksInfo[blockSha256Hash].timestamp != lastTimestamp) {
            return ERR_SUPERBLOCK_BAD_TIMESTAMP;
        }
        if (session.blocksInfo[blockSha256Hash].bits != lastBits) {
            return ERR_SUPERBLOCK_BAD_BITS;
        }
        if (session.blockHashes.length > 1) {
            blockSha256Hash = session.blockHashes[session.blockHashes.length - 2];
            if (session.blocksInfo[blockSha256Hash].timestamp != prevTimestamp) {
                return ERR_SUPERBLOCK_BAD_TIMESTAMP;
            }
        } else {
            (, , lastTimestamp, , , , , , ) = getSuperblockInfo(parentId);
            if (lastTimestamp != prevTimestamp) {
                return ERR_SUPERBLOCK_BAD_TIMESTAMP;
            }
        }
        return ERR_SUPERBLOCK_OK;
    }

    // Validate superblock accumulated work
    function validateProofOfWork(BattleSession storage session) internal view returns (uint) {
        uint accWork;
        uint parentWork;
        bytes32 parentId;
        bytes32 prevBlock;
        uint parentTimestamp;
        uint gpTimestamp;
        uint32 prevBits;
        (, accWork, , , , , parentId, , ) = getSuperblockInfo(session.superblockId);
        (, parentWork, parentTimestamp, gpTimestamp, prevBlock, prevBits, , , ) = getSuperblockInfo(parentId);
        uint idx = 0;
        uint work;
        while (idx < session.blockHashes.length) {
            bytes32 blockSha256Hash = session.blockHashes[idx];
            uint32 bits = session.blocksInfo[blockSha256Hash].bits;
            if (session.blocksInfo[blockSha256Hash].prevBlock != prevBlock) {
                return ERR_SUPERBLOCK_BAD_PARENT;
            }
            if (net != Network.REGTEST) {
                uint32 newBits = DogeTx.calculateDigishieldDifficulty(int64(parentTimestamp) - int64(gpTimestamp), prevBits);
                if (net == Network.TESTNET && session.blocksInfo[blockSha256Hash].timestamp - parentTimestamp > 120) {
                    newBits = 0x1e0fffff;
                }
                if (bits != newBits) {
                    return ERR_SUPERBLOCK_BAD_BITS;
                }
            }
            work += DogeTx.diffFromBits(session.blocksInfo[blockSha256Hash].bits);
            prevBlock = blockSha256Hash;
            prevBits = session.blocksInfo[blockSha256Hash].bits;
            gpTimestamp = parentTimestamp;
            parentTimestamp = session.blocksInfo[blockSha256Hash].timestamp;
            idx += 1;
        }
        if (net != Network.REGTEST && parentWork + work != accWork) {
            return ERR_SUPERBLOCK_BAD_ACCUMULATED_WORK;
        }
        return ERR_SUPERBLOCK_OK;
    }

    // @dev - Verify a superblock data is consistent
    // Only should be called when all blocks header were submitted
    function doVerifySuperblock(BattleSession storage session, bytes32 sessionId) internal returns (uint) {
        if (session.challengeState == ChallengeState.VerifyScryptHash) {
            skipScryptHashVerification(session);
        }
        if (session.challengeState == ChallengeState.PendingVerification) {
            uint err;
            err = validateLastBlocks(session);
            if (err != 0) {
                emit ErrorBattle(sessionId, err);
                return 2;
            }
            err = validateProofOfWork(session);
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
        uint status = doVerifySuperblock(session, sessionId);
        if (status == 1) {
            convictChallenger(sessionId, session.challenger, session.superblockId);
        } else if (status == 2) {
            convictSubmitter(sessionId, session.submitter, session.superblockId);
        }
    }

    // @dev - Able to trigger conviction if time of response is too high
    function timeout(bytes32 sessionId) public returns (uint) {
        BattleSession storage session = sessions[sessionId];
        if (session.challengeState == ChallengeState.PendingScryptVerification) {
            emit ErrorBattle(sessionId, ERR_SUPERBLOCK_NO_TIMEOUT);
            return ERR_SUPERBLOCK_NO_TIMEOUT;
        }
        if (session.lastActionChallenger > session.lastActionClaimant &&
            block.timestamp > session.lastActionTimestamp + superblockTimeout) {
            convictSubmitter(sessionId, session.submitter, session.superblockId);
            return ERR_SUPERBLOCK_OK;
        } else if (session.lastActionClaimant > session.lastActionChallenger &&
            block.timestamp > session.lastActionTimestamp + superblockTimeout) {
            convictChallenger(sessionId, session.challenger, session.superblockId);
            return ERR_SUPERBLOCK_OK;
        }
        emit ErrorBattle(sessionId, ERR_SUPERBLOCK_NO_TIMEOUT);
        return ERR_SUPERBLOCK_NO_TIMEOUT;
    }

    // @dev - To be called when a challenger is convicted
    function convictChallenger(bytes32 sessionId, address challenger, bytes32 superblockId) internal {
        BattleSession storage session = sessions[sessionId];
        sessionDecided(sessionId, superblockId, session.submitter, session.challenger);
        disable(sessionId);
        emit ChallengerConvicted(superblockId, sessionId, challenger);
    }

    // @dev - To be called when a submitter is convicted
    function convictSubmitter(bytes32 sessionId, address submitter, bytes32 superblockId) internal {
        BattleSession storage session = sessions[sessionId];
        sessionDecided(sessionId, superblockId, session.challenger, session.submitter);
        disable(sessionId);
        emit SubmitterConvicted(superblockId, sessionId, submitter);
    }

    // @dev - Disable session
    // It should be called only when either the submitter or the challenger were convicted.
    function disable(bytes32 sessionId) internal {
        delete sessions[sessionId];
    }

    // @dev Update scrypt verification result
    function notifyScryptHashResult(BattleSession storage session, bytes32 blockSha256Hash, bool valid) internal {
        BlockInfo storage blockInfo = session.blocksInfo[blockSha256Hash];
        if (valid){
            blockInfo.status = BlockInfoStatus.ScryptHashVerified;
            if (session.countBlockHeaderResponses == session.blockHashes.length) {
                session.challengeState = ChallengeState.PendingVerification;
            } else {
                session.challengeState = ChallengeState.RespondBlockHeader;
            }
        } else {
            blockInfo.status = BlockInfoStatus.ScryptHashFailed;
            session.challengeState = ChallengeState.SuperblockFailed;
        }
    }

    // @dev - Skip scrypt hash verification
    function skipScryptHashVerification(BattleSession storage session) internal {
        require(session.pendingScryptHashId != 0x0);
        bytes32 pendingScryptHashId = session.pendingScryptHashId;
        ScryptHashVerification storage verification = scryptHashVerifications[pendingScryptHashId];
        require(verification.sessionId != 0x0);
        notifyScryptHashResult(session, verification.blockSha256Hash, true);
        delete scryptHashVerifications[pendingScryptHashId];
        session.pendingScryptHashId = 0x0;
    }

    function compareBlockHeader(bytes left, bytes right) internal pure returns (int) {
        int a;
        int b;
        // Compare first 32 bytes
        assembly {
            a := mload(add(left, 0x20))
            b := mload(add(right, 0x20))
        }
        if (a != b) {
            return a - b;
        }
        // Compare next 32 bytes
        assembly {
            a := mload(add(left, 0x40))
            b := mload(add(right, 0x40))
        }
        if (a != b) {
            return a - b;
        }
        // Compare last 32 bytes
        assembly {
            a := mload(add(left, 0x50))
            b := mload(add(right, 0x50))
        }
        // Note: There's a 16 bytes overlap with previous 32 bytes chunk
        // But comparing full 32 bytes is faster/cheaper
        return a - b;
    }

    // @dev Scrypt verification submitted
    function scryptSubmitted(bytes32 scryptChallengeId, bytes32 _scryptHash, bytes _data, address _submitter) external onlyFrom(scryptChecker) {
        require(_data.length == 80);
        ScryptHashVerification storage verification = scryptHashVerifications[scryptChallengeId];
        BattleSession storage session = sessions[verification.sessionId];
        require(session.pendingScryptHashId == scryptChallengeId);
        require(session.challengeState == ChallengeState.RequestScryptVerification);
        require(session.submitter == _submitter);
        BlockInfo storage blockInfo = session.blocksInfo[verification.blockSha256Hash];
        require(blockInfo.status == BlockInfoStatus.ScryptHashPending);
        require(blockInfo.scryptHash == _scryptHash);
        require(compareBlockHeader(blockInfo.powBlockHeader, _data) == 0);
        session.challengeState = ChallengeState.PendingScryptVerification;
        session.actionsCounter += 1;
        session.lastActionTimestamp = block.timestamp;
        session.lastActionClaimant = session.actionsCounter;
    }

    function doNotifyScryptVerificationResult(bytes32 scryptChallengeId, bool succeeded) internal {
        ScryptHashVerification storage verification = scryptHashVerifications[scryptChallengeId];
        BattleSession storage session = sessions[verification.sessionId];
        require(session.pendingScryptHashId == scryptChallengeId);
        require(session.challengeState == ChallengeState.PendingScryptVerification);
        BlockInfo storage blockInfo = session.blocksInfo[verification.blockSha256Hash];
        require(blockInfo.status == BlockInfoStatus.ScryptHashPending);
        notifyScryptHashResult(session, verification.blockSha256Hash, succeeded);
        // Restart challenger timeout
        session.lastActionTimestamp = block.timestamp;
        emit ResolveScryptHashValidation(session.superblockId, verification.sessionId, blockInfo.scryptHash, scryptChallengeId, session.challenger, succeeded);
    }

    // @dev Scrypt verification succeeded
    function scryptVerified(bytes32 scryptChallengeId) external onlyFrom(scryptChecker) {
        doNotifyScryptVerificationResult(scryptChallengeId, true);
    }

    // @dev Scrypt verification failed
    function scryptFailed(bytes32 scryptChallengeId) external onlyFrom(scryptChecker) {
        doNotifyScryptVerificationResult(scryptChallengeId, false);
    }

    // @dev - Check if a session's challenger did not respond before timeout
    function getChallengerHitTimeout(bytes32 sessionId) public view returns (bool) {
        BattleSession storage session = sessions[sessionId];
        return (session.challengeState != ChallengeState.PendingScryptVerification &&
        session.lastActionClaimant > session.lastActionChallenger &&
        block.timestamp > session.lastActionTimestamp + superblockTimeout);
    }

    // @dev - Check if a session's submitter did not respond before timeout
    function getSubmitterHitTimeout(bytes32 sessionId) public view returns (bool) {
        BattleSession storage session = sessions[sessionId];
        return (session.challengeState != ChallengeState.PendingScryptVerification &&
        session.lastActionChallenger > session.lastActionClaimant &&
        block.timestamp > session.lastActionTimestamp + superblockTimeout);
    }

    // @dev - Return Doge block hashes associated with a certain battle session
    function getDogeBlockHashes(bytes32 sessionId) public view returns (bytes32[]) {
        return sessions[sessionId].blockHashes;
    }

    // @dev - To be called when a battle sessions  was decided
    function sessionDecided(bytes32 sessionId, bytes32 superblockId, address winner, address loser) internal;

    // @dev - Retrieve superblock information
    function getSuperblockInfo(bytes32 superblockId) internal view returns (
        bytes32 _blocksMerkleRoot,
        uint _accumulatedWork,
        uint _timestamp,
        uint _prevTimestamp,
        bytes32 _lastHash,
        uint32 _lastBits,
        bytes32 _parentId,
        address _submitter,
        DogeSuperblocks.Status _status
    );

    // FIXME: Using directly getDeposit forces DogeBattleManager
    // to inherit from DogeDepositsManager.
    function getDepositInternal(address who) internal view returns (uint);

    function bondDeposit(bytes32 claimId, address account, uint amount) internal returns (uint, uint);

    function unbondDeposit(bytes32 claimId, address account) internal returns (uint, uint);
}

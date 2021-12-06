// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import {SuperblockClaims} from "./SuperblockClaims.sol";
import {DogeErrorCodes} from "./DogeErrorCodes.sol";
import {DogeSuperblocks} from "./DogeSuperblocks.sol";
import {DogeMessageLibrary} from "./DogeParser/DogeMessageLibrary.sol";
import {IScryptChecker} from "./scrypt-interactive/IScryptChecker.sol";
import {IScryptCheckerListener} from "./scrypt-interactive/IScryptCheckerListener.sol";

// @dev - Manages a battle session between superblock submitter and challenger
contract DogeBattleManager is DogeErrorCodes, IScryptCheckerListener {

    enum ChallengeState {
        /**
         * Unchallenged submission
         * This is not in use. TODO: remove?
         */
        Unchallenged,
        /**
         * Claim was challenged
         */
        Challenged,
        /**
         * Challenger is expecting block hashes
         */
        QueryMerkleRootHashes,
        /**
         * Block hashes were received and verified
         */
        RespondMerkleRootHashes,
        /**
         * Challenger is requesting block headers
         */
        QueryBlockHeader,
        /**
         * All block headers were received
         */
        RespondBlockHeader,
        /**
         * The block header scrypt hash validation can be requested now.
         */
        VerifyScryptHash,
        /**
         * The block header scrypt hash validation was requested.
         * This means that the superblock submitter is expected to submit the scrypt hash claim
         * and defend it in the ScryptVerifier contract.
         */
        RequestScryptVerification,
        /**
         * Pending scrypt hash verification
         * The scrypt hash claim was submitted and is in the process of being defended.
         * Here, the session is paused while the battle continues in the ScryptVerifier contract.
         */
        PendingScryptVerification,
        /**
         * Pending final superblock verification
         */
        PendingVerification,
        /**
         * Superblock is verified.
         * This is not in use. TODO: remove?
         */
        // SuperblockVerified,
        /**
         * Superblock verification failed.
         */
        SuperblockFailed
    }

    enum BlockInfoStatus {
        Nonexistent,
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
        bytes32 superblockHash;
        address submitter;
        address challenger;
        // Last action timestamp
        uint lastActionTimestamp;
        // Number last action submitter
        uint lastActionClaimant;
        // Number last action challenger
        uint lastActionChallenger;
        // Counter session actions
        uint actionsCounter;

        // Block hashes
        bytes32[] blockHashes;
        // Number of block header queries
        uint countBlockHeaderQueries;
        // Number of block header responses
        uint countBlockHeaderResponses;

        mapping (bytes32 => BlockInfo) blocksInfo;

        bytes32 pendingScryptHashId;

        // Claim state
        ChallengeState challengeState;
    }

    struct ScryptHashVerification {
        bytes32 sessionId;
        bytes32 blockSha256Hash;
    }

    mapping (bytes32 => BattleSession) public sessions;

    uint public sessionsCount;

    // Superblock duration (in seconds)
    uint public superblockDuration;
    // Timeout action (in seconds)
    uint public superblockTimeout;

    // Pending Scrypt Hash verifications
    uint public numScryptHashVerifications;

    mapping (bytes32 => ScryptHashVerification) public scryptHashVerifications;

    // network that the stored blocks belong to
    DogeMessageLibrary.Network private net;

    // ScryptHash checker
    IScryptChecker public trustedScryptChecker;

    // Doge claim manager
    SuperblockClaims trustedSuperblockClaims;

    // Superblocks contract
    DogeSuperblocks trustedSuperblocks;

    event NewBattle(bytes32 superblockHash, bytes32 sessionId, address submitter, address challenger);
    event ChallengerConvicted(bytes32 superblockHash, bytes32 sessionId, address challenger);
    event SubmitterConvicted(bytes32 superblockHash, bytes32 sessionId, address submitter);

    event QueryMerkleRootHashes(bytes32 superblockHash, bytes32 sessionId, address submitter);
    event RespondMerkleRootHashes(bytes32 superblockHash, bytes32 sessionId, address challenger, bytes32[] blockHashes);
    event QueryBlockHeader(bytes32 superblockHash, bytes32 sessionId, address submitter, bytes32 blockSha256Hash);

    event RespondBlockHeader(bytes32 superblockHash, bytes32 sessionId, address challenger, bytes32 blockScryptHash,
    bytes blockHeader, bytes powBlockHeader);

    event RequestScryptHashValidation(bytes32 superblockHash, bytes32 sessionId, bytes32 blockScryptHash,
    bytes blockHeader, bytes32 proposalId, address submitter);

    event ResolvedScryptHashValidation(bytes32 superblockHash, bytes32 sessionId, bytes32 blockScryptHash,
    bytes32 blockSha256Hash, bytes32 proposalId, address challenger, bool valid);

    event ErrorBattle(bytes32 sessionId, uint err);

    modifier onlyScryptChecker() {
        require(msg.sender == address(trustedScryptChecker), "ERR_AUTH_ONLY_SCRYPTCHECKER");
        _;
    }

    modifier onlySuperblockClaims() {
        require(msg.sender == address(trustedSuperblockClaims), "ERR_AUTH_ONLY_SUPERBLOCKCLAIMS");
        _;
    }

    modifier onlyClaimant(bytes32 sessionId) {
        require(msg.sender == sessions[sessionId].submitter, "ERR_AUTH_ONLY_CLAIMANT");
        _;
    }

    modifier onlyChallenger(bytes32 sessionId) {
        require(msg.sender == sessions[sessionId].challenger, "ERR_AUTH_ONLY_CHALLENGER");
        _;
    }

    /**
     * Initializer functions
     * Deferred initialization is necessary for the SuperblockClaims contract due to the fact
     * that the battle manager and superblock claims contracts mutually depend on each other.
     */

    /**
     * @dev – Configures the contract managing superblocks battles
     * @param network Network type to use for block difficulty validation
     * @param superblocks Contract that stores superblocks
     * @param scryptChecker Contract that verifies scrypt hashes.
     * @param initSuperblockDuration Superblock duration (in seconds)
     * @param initSuperblockTimeout Time to wait for challenges (in seconds)
     */
    function initialize(
        DogeMessageLibrary.Network network,
        DogeSuperblocks superblocks,
        IScryptChecker scryptChecker,
        uint initSuperblockDuration,
        uint initSuperblockTimeout
    ) external {
        require(address(trustedSuperblocks) == address(0), "DogeBattleManager already initialized.");
        require(address(superblocks) != address(0), "Superblocks contract must be valid.");
        require(address(scryptChecker) != address(0x0), "Scrypt checker must be valid.");

        net = network;
        trustedSuperblocks = superblocks;
        trustedScryptChecker = scryptChecker;
        superblockDuration = initSuperblockDuration;
        superblockTimeout = initSuperblockTimeout;
    }


    /**
     * @dev - sets SuperblockClaims instance associated with this DogeBattleManager contract.
     * Once set, it cannot be reset.
     * The SuperblockClaims contract is used in battle creation and resolution.
     *
     * @param superblockClaims Address of the SuperblockClaims contract.
     */
    function setSuperblockClaims(SuperblockClaims superblockClaims) public {
        require(address(trustedSuperblockClaims) == address(0x0), "SuperblockClaims is already set!");
        require(address(superblockClaims) != address(0x0), "Superblock claims contract must be valid.");
        trustedSuperblockClaims = superblockClaims;
    }

    /**
     * Battle functions
     */

    /**
     * @dev - Start a battle session
     */
    function beginBattleSession(bytes32 superblockHash, address submitter, address challenger)
    external onlySuperblockClaims returns (bytes32) {
        bytes32 sessionId = keccak256(abi.encode(superblockHash, msg.sender, sessionsCount));
        BattleSession storage session = sessions[sessionId];
        session.id = sessionId;
        session.superblockHash = superblockHash;
        session.submitter = submitter;
        session.challenger = challenger;
        session.lastActionTimestamp = block.timestamp;
        session.lastActionChallenger = 0;
        // Force challenger to start
        session.lastActionClaimant = 1;
        session.actionsCounter = 1;
        session.challengeState = ChallengeState.Challenged;

        sessionsCount += 1;

        emit NewBattle(superblockHash, sessionId, submitter, challenger);
        return sessionId;
    }

    /**
     * @dev Challenger makes a query for superblock hashes
     */
    function queryMerkleRootHashes(bytes32 superblockHash, bytes32 sessionId) public onlyChallenger(sessionId) {
        BattleSession storage session = sessions[sessionId];

        // This is redundant. If the challenger doesn't have enough eth deposited, `bondDeposit` will fail.
        // However, it allows giving a custom error message here.
        // Error: There is not enough eth deposited to bond for the payment of the next step in the battle.
        require(hasDeposit(msg.sender, respondMerkleRootHashesCost), "ERR_QUERY_MERKLE_NEEDS_DEPOSIT");
        // Error: The battle does not allow querying the merkle root hashes of the blocks now.
        require(session.challengeState == ChallengeState.Challenged, "ERR_QUERY_MERKLE_INCORRECT_STEP");

        session.challengeState = ChallengeState.QueryMerkleRootHashes;
        bondDeposit(session.superblockHash, msg.sender, respondMerkleRootHashesCost);

        session.actionsCounter += 1;
        session.lastActionTimestamp = block.timestamp;
        session.lastActionChallenger = session.actionsCounter;
        emit QueryMerkleRootHashes(superblockHash, sessionId, session.submitter);
    }

    /**
     * @dev Submitter sends hashes to verify superblock merkle root
     * For the submitter to respond to challenger queries
     */
    function respondMerkleRootHashes(
        bytes32 superblockHash,
        bytes32 sessionId,
        bytes32[] calldata blockHashes
    ) public onlyClaimant(sessionId) {
        BattleSession storage session = sessions[sessionId];

        // Error: There is not enough eth deposited to bond for the payment of the next step in the battle.
        require(hasDeposit(msg.sender, verifySuperblockCost), "ERR_VERIFY_MERKLE_NEEDS_DEPOSIT");

        // Error: A superblock must contain at least one block.
        require(session.blockHashes.length == 0, "ERR_VERIFY_MERKLE_BLOCK_HASHES_MISSING");
        // Error: The battle does not allow verifying the merkle root hashes of the blocks now.
        require(session.challengeState == ChallengeState.QueryMerkleRootHashes, "ERR_VERIFY_MERKLE_INCORRECT_STEP");

        (bytes32 merkleRoot, , , , bytes32 lastHash, , , , ) = getSuperblockInfo(session.superblockHash);
        // Error: The last block hash is inconsistent with the one submitted for this superblock.
        require(lastHash == blockHashes[blockHashes.length - 1], "ERR_VERIFY_MERKLE_BAD_LASTBLOCK");
        // Error: The merkle root of block hashes is inconsistent with the one submitted for this superblock.
        require(merkleRoot == DogeMessageLibrary.makeMerkle(blockHashes), "ERR_VERIFY_MERKLE_INVALID_MERKLE");

        bondDeposit(session.superblockHash, msg.sender, verifySuperblockCost);

        session.blockHashes = blockHashes;
        session.challengeState = ChallengeState.RespondMerkleRootHashes;

        session.actionsCounter += 1;
        session.lastActionTimestamp = block.timestamp;
        session.lastActionClaimant = session.actionsCounter;

        // Map blocks to prevent a malicious challenger from requesting one that doesn't exist
        for (uint i = 0; i < blockHashes.length; ++i) {
            session.blocksInfo[blockHashes[i]].status = BlockInfoStatus.Uninitialized;
        }

        emit RespondMerkleRootHashes(superblockHash, sessionId, session.challenger, blockHashes);
    }

    /**
     * @dev Challenger queries the block header data for a hash
     */
    function queryBlockHeader(
        bytes32 superblockHash,
        bytes32 sessionId,
        bytes32 blockHash
    ) public onlyChallenger(sessionId) {
        BattleSession storage session = sessions[sessionId];

        // Error: There is not enough eth deposited to bond for the payment of the next step in the battle.
        require(hasDeposit(msg.sender, respondBlockHeaderCost), "ERR_QUERY_BLOCK_NEEDS_DEPOSIT");

        if (session.challengeState == ChallengeState.VerifyScryptHash) {
            skipScryptHashVerification(session);
        }

        // Error: The battle does not allow querying a block header now. 
        require(
            (session.countBlockHeaderQueries == 0 && session.challengeState == ChallengeState.RespondMerkleRootHashes) ||
            (session.countBlockHeaderQueries > 0 && session.challengeState == ChallengeState.RespondBlockHeader),
            "ERR_QUERY_BLOCK_INCORRECT_STEP"
        );

        // Error: All block headers were queried already.
        require(session.countBlockHeaderQueries < session.blockHashes.length, "ERR_QUERY_BLOCK_ALL_BLOCKS_QUERIED");
        // Error: This block header was queried already.
        require(
            session.blocksInfo[blockHash].status == BlockInfoStatus.Uninitialized,
            "ERR_QUERY_BLOCK_ALREADY_QUERIED"
        );

        bondDeposit(session.superblockHash, msg.sender, respondBlockHeaderCost);
        session.countBlockHeaderQueries += 1;
        session.blocksInfo[blockHash].status = BlockInfoStatus.Requested;
        session.challengeState = ChallengeState.QueryBlockHeader;

        session.actionsCounter += 1;
        session.lastActionTimestamp = block.timestamp;
        session.lastActionChallenger = session.actionsCounter;
        emit QueryBlockHeader(superblockHash, sessionId, session.submitter, blockHash);
    }

    // @dev - Verify that block timestamp is in the superblock timestamp interval
    function verifyTimestamp(bytes32 superblockHash, bytes memory blockHeader) internal view returns (bool) {
        uint blockTimestamp = DogeMessageLibrary.getTimestamp(blockHeader, 0);
        uint superblockTimestamp;

        (, , superblockTimestamp, , , , , , ) = getSuperblockInfo(superblockHash);

        // Block timestamp to be within the expected timestamp of the superblock
        return (blockTimestamp / superblockDuration <= superblockTimestamp / superblockDuration)
            && (blockTimestamp / superblockDuration >= superblockTimestamp / superblockDuration - 1);
    }

    // @dev - Generate request to verify block header scrypt hash
    function doVerifyScryptHash(
        bytes32 sessionId,
        bytes32 blockScryptHash,
        bytes32 blockSha256Hash,
        address submitter
    ) internal returns (bytes32) {
        numScryptHashVerifications += 1;
        bytes32 proposalId = keccak256(abi.encodePacked(
            blockScryptHash,
            submitter,
            numScryptHashVerifications
        ));

        scryptHashVerifications[proposalId] = ScryptHashVerification({
            sessionId: sessionId,
            blockSha256Hash: blockSha256Hash
        });

        return proposalId;
    }

    // @dev - Verify Dogecoin block AuxPoW
    function verifyBlockAuxPoW(
        BlockInfo storage blockInfo,
        bytes32 proposedBlockScryptHash,
        bytes memory blockHeader
    ) internal returns (uint, bytes memory) {
        (uint err, , uint blockScryptHash, bool isMergeMined) =
            DogeMessageLibrary.verifyBlockHeader(blockHeader, 0, blockHeader.length, uint(proposedBlockScryptHash));
        if (err != 0) {
            return (err, new bytes(0));
        }
        bytes memory powBlockHeader = (isMergeMined) ?
            DogeMessageLibrary.sliceArray(blockHeader, blockHeader.length - 80, blockHeader.length) :
            DogeMessageLibrary.sliceArray(blockHeader, 0, 80);

        blockInfo.timestamp = DogeMessageLibrary.getTimestamp(blockHeader, 0);
        blockInfo.bits = DogeMessageLibrary.getBits(blockHeader, 0);
        blockInfo.prevBlock = bytes32(DogeMessageLibrary.getHashPrevBlock(blockHeader, 0));
        blockInfo.scryptHash = bytes32(blockScryptHash);
        blockInfo.powBlockHeader = powBlockHeader;
        return (ERR_SUPERBLOCK_OK, powBlockHeader);
    }

    // @dev - Verify block header sent by superblock submitter
    function doVerifyBlockHeader(
        BattleSession storage session,
        bytes32 sessionId,
        bytes32 proposedBlockScryptHash,
        bytes memory blockHeader
    ) internal returns (uint, bytes memory) {
        // TODO: see if this should fund Scrypt verification
        if (!hasDeposit(msg.sender, respondBlockHeaderCost)) {
            return (ERR_SUPERBLOCK_MIN_DEPOSIT, new bytes(0));
        }

        // TODO: have this revert instead
        if (session.challengeState != ChallengeState.QueryBlockHeader) {
            return (ERR_SUPERBLOCK_BAD_STATUS, new bytes(0));
        }

        bytes32 blockSha256Hash = bytes32(DogeMessageLibrary.dblShaFlipMem(blockHeader, 0, 80));
        BlockInfo storage blockInfo = session.blocksInfo[blockSha256Hash];
        if (blockInfo.status != BlockInfoStatus.Requested) {
            return (ERR_SUPERBLOCK_BAD_DOGE_STATUS, new bytes(0));
        }

        if (!verifyTimestamp(session.superblockHash, blockHeader)) {
            return (ERR_SUPERBLOCK_BAD_TIMESTAMP, new bytes(0));
        }

        (uint err, bytes memory powBlockHeader) =
            verifyBlockAuxPoW(blockInfo, proposedBlockScryptHash, blockHeader);
        if (err != ERR_SUPERBLOCK_OK) {
            return (err, new bytes(0));
        }

        blockInfo.status = BlockInfoStatus.ScryptHashPending;

        bondDeposit(session.superblockHash, msg.sender, respondBlockHeaderCost);

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

    // @dev - For the submitter to respond to challenger queries
    function respondBlockHeader(
        bytes32 superblockHash,
        bytes32 sessionId,
        bytes32 blockScryptHash,
        bytes calldata blockHeader
    ) public onlyClaimant(sessionId) {
        BattleSession storage session = sessions[sessionId];
        (uint err, bytes memory powBlockHeader) = doVerifyBlockHeader(session, sessionId, blockScryptHash, blockHeader);
        // TODO: add error code with custom errors in Solidity v0.8
        require(err == 0, "Failed while verifying block header.");

        session.actionsCounter += 1;
        session.lastActionTimestamp = block.timestamp;
        session.lastActionClaimant = session.actionsCounter;
        emit RespondBlockHeader(superblockHash, sessionId, session.challenger, blockScryptHash, blockHeader, powBlockHeader);
    }

    /**
     * @dev - Challenger requests to start scrypt hash verification
     */
    function requestScryptHashValidation(
        bytes32 superblockHash,
        bytes32 sessionId,
        bytes32 blockSha256Hash
    ) public onlyChallenger(sessionId) {
        BattleSession storage session = sessions[sessionId];

        // Error: There is not enough eth deposited to bond for the payment of the next step in the battle.
        require(hasDeposit(msg.sender, queryMerkleRootHashesCost), "ERR_REQUEST_SCRYPT_NEEDS_DEPOSIT");

        // Error: The battle does not allow requesting validation of a scrypt hash now.
        require(session.challengeState == ChallengeState.VerifyScryptHash, "ERR_REQUEST_SCRYPT_INCORRECT_STEP");

        BlockInfo storage blockInfo = session.blocksInfo[blockSha256Hash];
        // Error: This block is either already verified or its header wasn't requested yet.
        require(blockInfo.status == BlockInfoStatus.ScryptHashPending, "ERR_REQUEST_SCRYPT_INCORRECT_BLOCK_STEP");

        bondDeposit(session.superblockHash, msg.sender, queryMerkleRootHashesCost);

        emit RequestScryptHashValidation(superblockHash, sessionId, blockInfo.scryptHash, blockInfo.powBlockHeader, session.pendingScryptHashId, session.submitter);
        session.challengeState = ChallengeState.RequestScryptVerification;

        session.actionsCounter += 1;
        session.lastActionTimestamp = block.timestamp;
        session.lastActionChallenger = session.actionsCounter;
    }

    /**
     * @dev - Validate superblock information from last blocks
     */
    function validateLastBlocks(BattleSession storage session) internal view returns (uint) {
        if (session.blockHashes.length <= 0) {
            return ERR_SUPERBLOCK_BAD_LASTBLOCK;
        }
        uint lastTimestamp;
        uint prevTimestamp;
        uint32 lastBits;
        bytes32 parentId;
        (, , lastTimestamp, prevTimestamp, , lastBits, parentId, , ) = getSuperblockInfo(session.superblockHash);
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

    /**
     * @dev - Validate superblock accumulated work
     */
    function validateProofOfWork(BattleSession storage session) internal view returns (uint) {
        uint accWork;
        uint parentWork;
        bytes32 parentId;
        bytes32 prevBlock;
        uint parentTimestamp;
        uint gpTimestamp;
        uint32 prevBits;
        (, accWork, , , , , parentId, , ) = getSuperblockInfo(session.superblockHash);
        (, parentWork, parentTimestamp, gpTimestamp, prevBlock, prevBits, , , ) = getSuperblockInfo(parentId);
        uint idx = 0;
        uint work;
        // TODO: ensure this doesn't result in excessive gas costs
        // We may need to allow partial computation of this verification.
        while (idx < session.blockHashes.length) {
            bytes32 blockSha256Hash = session.blockHashes[idx];
            // TODO: add missing test for this case.
            if (session.blocksInfo[blockSha256Hash].prevBlock != prevBlock) {
                return ERR_SUPERBLOCK_BAD_PARENT;
            }
            uint32 bits = session.blocksInfo[blockSha256Hash].bits;
            if (net != DogeMessageLibrary.Network.REGTEST) {
                uint32 newBits = DogeMessageLibrary.calculateDigishieldDifficulty(
                    int64(parentTimestamp) - int64(gpTimestamp), prevBits);
                if (net == DogeMessageLibrary.Network.TESTNET &&
                session.blocksInfo[blockSha256Hash].timestamp - parentTimestamp > 120) {
                    newBits = 0x1e0fffff;
                }
                if (bits != newBits) {
                    return ERR_SUPERBLOCK_BAD_BITS;
                }
            }
            work += DogeMessageLibrary.diffFromBits(session.blocksInfo[blockSha256Hash].bits);
            prevBlock = blockSha256Hash;
            prevBits = session.blocksInfo[blockSha256Hash].bits;
            gpTimestamp = parentTimestamp;
            parentTimestamp = session.blocksInfo[blockSha256Hash].timestamp;
            idx += 1;
        }
        if (net != DogeMessageLibrary.Network.REGTEST && parentWork + work != accWork) {
            return ERR_SUPERBLOCK_BAD_ACCUMULATED_WORK;
        }
        return ERR_SUPERBLOCK_OK;
    }

    // @dev - Verify whether a superblock's data is consistent
    // Should only be called when all block headers were submitted
    // @return 0 when we can't verify it yet. 1 when the challenger loses. 2 when the submitter loses.
    function doVerifySuperblock(BattleSession storage session, bytes32 sessionId) internal returns (uint) {
        if (session.challengeState == ChallengeState.VerifyScryptHash) {
            skipScryptHashVerification(session);
        }

        if (session.challengeState == ChallengeState.SuperblockFailed) {
            return 2;
        }

        // If the superblock is not ready for the final verification, we shouldn't do anything.
        // Error: Either the superblock cannot be verified yet or it was already verified.
        require(session.challengeState == ChallengeState.PendingVerification, "ERR_VERIFY_SUPERBLOCK_INCORRECT_STEP");

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
    }

    // @dev - Perform final verification once all blocks were submitted
    function verifySuperblock(bytes32 sessionId) public {
        BattleSession storage session = sessions[sessionId];
        uint status = doVerifySuperblock(session, sessionId);
        if (status == 1) {
            convictChallenger(sessionId, session.challenger, session.superblockHash);
        } else if (status == 2) {
            convictSubmitter(sessionId, session.submitter, session.superblockHash);
        }
    }

    // @dev - Trigger conviction if response is not received in time
    function timeout(bytes32 sessionId) public returns (uint) {
        BattleSession storage session = sessions[sessionId];
        // Error: The battle can't be timed out during scrypt verification.
        require(
            session.challengeState != ChallengeState.PendingScryptVerification,
            "ERR_BATTLE_TIMEOUT_PENDING_SCRYPT_VERIFICATION"
        );

        if (session.challengeState == ChallengeState.SuperblockFailed ||
            (session.lastActionChallenger > session.lastActionClaimant &&
            block.timestamp > session.lastActionTimestamp + superblockTimeout)) {
            convictSubmitter(sessionId, session.submitter, session.superblockHash);
            return ERR_SUPERBLOCK_OK;
        } else if (session.lastActionClaimant > session.lastActionChallenger &&
            block.timestamp > session.lastActionTimestamp + superblockTimeout) {
            convictChallenger(sessionId, session.challenger, session.superblockHash);
            return ERR_SUPERBLOCK_OK;
        }
        // Error: No timeout can be enacted at this point in the battle.
        revert("ERR_BATTLE_TIMEOUT_NO_TIMEOUT");
    }

    // @dev - To be called when a challenger is convicted
    function convictChallenger(bytes32 sessionId, address challenger, bytes32 superblockHash) internal {
        // TODO: session should be a parameter
        BattleSession storage session = sessions[sessionId];
        sessionDecided(sessionId, superblockHash, session.submitter, session.challenger);
        disable(sessionId);
        emit ChallengerConvicted(superblockHash, sessionId, challenger);
    }

    // @dev - To be called when a submitter is convicted
    function convictSubmitter(bytes32 sessionId, address submitter, bytes32 superblockHash) internal {
        // TODO: session should be a parameter
        BattleSession storage session = sessions[sessionId];
        sessionDecided(sessionId, superblockHash, session.challenger, session.submitter);
        disable(sessionId);
        emit SubmitterConvicted(superblockHash, sessionId, submitter);
    }

    // @dev - Disable session
    // It should be called only when either the submitter or the challenger were convicted.
    function disable(bytes32 sessionId) internal {
        // TODO: Careful!! A `BattleSession` has a field that is an array type.
        // If this implies its deletion, then it could have an unexpected gas cost.
        // The blockHashes array size is currently bounded by what fits in a single transaction,
        // but this might not be enough to ensure that the gas cost does not go over the block gas limit.
        delete sessions[sessionId];
    }

    // @dev Update scrypt verification result
    function notifyScryptHashResult(
        BattleSession storage session,
        bytes32 blockSha256Hash,
        bool valid
    ) internal {
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

    // @dev - Compare two 80-byte Doge block headers
    function compareBlockHeader(bytes memory left, bytes memory right) internal pure returns (int) {
        require(left.length == 80);
        require(right.length == 80);
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

    // @dev - To be called after scrypt verification is submitted
    function scryptSubmitted(
        bytes32 scryptChallengeId,
        bytes32 scryptHash,
        bytes calldata data,
        address submitter
    ) override external onlyScryptChecker {
        require(data.length == 80);
        ScryptHashVerification storage verification = scryptHashVerifications[scryptChallengeId];
        BattleSession storage session = sessions[verification.sessionId];
        require(session.pendingScryptHashId == scryptChallengeId);
        require(session.challengeState == ChallengeState.RequestScryptVerification);
        require(session.submitter == submitter);
        BlockInfo storage blockInfo = session.blocksInfo[verification.blockSha256Hash];
        require(blockInfo.status == BlockInfoStatus.ScryptHashPending);
        require(blockInfo.scryptHash == scryptHash);
        require(compareBlockHeader(blockInfo.powBlockHeader, data) == 0);
        session.challengeState = ChallengeState.PendingScryptVerification;
        session.actionsCounter += 1;
        session.lastActionTimestamp = block.timestamp;
        session.lastActionClaimant = session.actionsCounter;
    }

    // @dev - Update session state with scrypt hash verification result
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
        emit ResolvedScryptHashValidation(
            session.superblockHash,
            verification.sessionId,
            blockInfo.scryptHash,
            verification.blockSha256Hash,
            scryptChallengeId,
            session.challenger,
            succeeded
        );
    }

    // @dev - Scrypt verification succeeded
    function scryptVerified(bytes32 scryptChallengeId) override external onlyScryptChecker {
        doNotifyScryptVerificationResult(scryptChallengeId, true);
    }

    // @dev - Scrypt verification failed
    function scryptFailed(bytes32 scryptChallengeId) override external onlyScryptChecker {
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
    function getDogeBlockHashes(bytes32 sessionId) public view returns (bytes32[] memory) {
        return sessions[sessionId].blockHashes;
    }

    // @dev - To be called when a battle sessions  was decided
    function sessionDecided(bytes32 sessionId, bytes32 superblockHash, address winner, address loser) internal {
        trustedSuperblockClaims.sessionDecided(sessionId, superblockHash, winner, loser);
    }

    // @dev - Retrieve superblock information
    function getSuperblockInfo(bytes32 superblockHash) internal view returns (
        bytes32 blocksMerkleRoot,
        uint accumulatedWork,
        uint timestamp,
        uint prevTimestamp,
        bytes32 lastHash,
        uint32 lastBits,
        bytes32 parentId,
        address submitter,
        DogeSuperblocks.Status status
    ) {
        return trustedSuperblocks.getSuperblock(superblockHash);
    }

    // @dev - Verify whether a user has a certain amount of deposits or more
    function hasDeposit(address who, uint amount) internal view returns (bool) {
        return trustedSuperblockClaims.getDeposit(who) >= amount;
    }

    // @dev – locks up part of a user's deposit into a claim.
    function bondDeposit(bytes32 superblockHash, address account, uint amount) internal returns (uint) {
        return trustedSuperblockClaims.bondDeposit(superblockHash, account, amount);
    }
}

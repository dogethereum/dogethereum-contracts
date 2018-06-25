pragma solidity ^0.4.19;

import {DogeErrorCodes} from "./DogeErrorCodes.sol";


// @dev - Manages a battle session between superblock submitter and challenger
contract DogeBattleManager is DogeErrorCodes {

    event NewSession(bytes32 sessionId, address claimant, address challenger);
    event ChallengerConvicted(bytes32 sessionId, address challenger);
    event ClaimantConvicted(bytes32 sessionId, address claimant);

    event QueryMerkleRootHashes(bytes32 sessionId, address claimant);
    event RespondMerkleRootHashes(bytes32 sessionId, address challenger, bytes32[] blockHashes);
    event QueryBlockHeader(bytes32 sessionId, address claimant, bytes32 blockHash);
    event RespondBlockHeader(bytes32 sessionId, address challenger, bytes32 scryptBlockHash, bytes blockHeader);

    event SessionError(bytes32 sessionId, uint err);

    struct BattleSession {
        bytes32 id;
        bytes32 claimId;
        address claimant;
        address challenger;
        uint lastActionTimestamp;         // Last action timestamp
        uint lastActionClaimant;          // Number last action claimant
        uint lastActionChallenger;        // Number last action challenger
        uint actionsCounter;              // Counter session actions
    }

    modifier onlyClaimant(bytes32 sessionId) {
        require(msg.sender == sessions[sessionId].claimant);
        _;
    }

    modifier onlyChallenger(bytes32 sessionId) {
        require(msg.sender == sessions[sessionId].challenger);
        _;
    }

    mapping(bytes32 => BattleSession) public sessions;

    uint public sessionsCount = 0;

    uint public superblockTimeout;        // Timeout action (in seconds)

    constructor(uint _superblockTimeout) public {
        superblockTimeout = _superblockTimeout;
    }

    // @dev - Start a battle session
    function beginBattleSession(bytes32 claimId, address challenger, address claimant) public returns (bytes32) {
        bytes32 sessionId = keccak256(abi.encode(claimId, msg.sender, sessionsCount));
        BattleSession storage session = sessions[sessionId];
        session.id = sessionId;
        session.claimId = claimId;
        session.claimant = claimant;
        session.challenger = challenger;
        session.lastActionTimestamp = block.timestamp;
        session.lastActionChallenger = 0;
        session.lastActionClaimant = 1;     // Force challenger to start
        session.actionsCounter = 1;

        sessionsCount += 1;

        emit NewSession(sessionId, claimant, challenger);
        return sessionId;
    }

    // @dev - Challenger makes a query for superblock hashes
    function doQueryMerkleRootHashes(bytes32 claimId) internal returns (bool);

    // @dev - Challenger makes a query for block header data for a hash
    function doQueryBlockHeader(bytes32 claimId, bytes32 blockHash) internal returns (bool);

    // @dev - Challenger makes a query for superblock hashes
    function queryMerkleRootHashes(bytes32 sessionId) onlyChallenger(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        bytes32 claimId = session.claimId;
        bool succeeded = false;
        succeeded = doQueryMerkleRootHashes(claimId);
        if (succeeded) {
            session.actionsCounter += 1;
            session.lastActionTimestamp = block.timestamp;
            session.lastActionChallenger = session.actionsCounter;
            emit QueryMerkleRootHashes(sessionId, session.claimant);
        }
    }

    // @dev - For the challenger to start a query
    function queryBlockHeader(bytes32 sessionId, bytes32 blockHash) onlyChallenger(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        bytes32 claimId = session.claimId;
        bool succeeded = false;
        succeeded = doQueryBlockHeader(claimId, blockHash);
        if (succeeded) {
            session.actionsCounter += 1;
            session.lastActionTimestamp = block.timestamp;
            session.lastActionChallenger = session.actionsCounter;
            emit QueryBlockHeader(sessionId, session.claimant, blockHash);
        }
    }

    // @dev - Submitter send hashes to verify superblock merkle root
    function verifyMerkleRootHashes(bytes32 claimId, bytes32[] blockHashes) internal returns (bool);

    // @dev - Verify block header send by challenger
    function verifyBlockHeader(bytes32 claimId, bytes32 scryptBlockHash, bytes blockHeader) internal returns (bool);

    // @dev - For the submitter to respond to challenger queries
    function respondMerkleRootHashes(bytes32 sessionId, bytes32[] blockHashes) onlyClaimant(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        bytes32 claimId = session.claimId;
        bool succeeded = false;
        succeeded = verifyMerkleRootHashes(claimId, blockHashes);
        if (succeeded) {
            session.actionsCounter += 1;
            session.lastActionTimestamp = block.timestamp;
            session.lastActionClaimant = session.actionsCounter;
            emit RespondMerkleRootHashes(sessionId, session.challenger, blockHashes);
        }
    }

    // @dev - For the submitter to respond to challenger queries
    function respondBlockHeader(bytes32 sessionId, bytes32 scryptBlockHash, bytes blockHeader) onlyClaimant(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        bytes32 claimId = session.claimId;
        bool succeeded = false;
        succeeded = verifyBlockHeader(claimId, scryptBlockHash, blockHeader);
        if (succeeded) {
            session.actionsCounter += 1;
            session.lastActionTimestamp = block.timestamp;
            session.lastActionClaimant = session.actionsCounter;
            emit RespondBlockHeader(sessionId, session.challenger, scryptBlockHash, blockHeader);
        }
    }

    // @dev - Verify a superblock data is consistent
    // Only should be called when all blocks header were submitted
    function verifySuperblock(bytes32 claimId) internal returns (bool);

    // @dev - Perform final verification once all blocks were submitted
    function performVerification(bytes32 sessionId) public  {
        BattleSession storage session = sessions[sessionId];
        bytes32 claimId = session.claimId;
        if (verifySuperblock(claimId)) {
            challengerConvicted(sessionId, session.challenger, claimId);
        } else {
            claimantConvicted(sessionId, session.claimant, claimId);
        }
    }

    // @dev - Able to trigger conviction if time of response is too high
    function timeout(bytes32 sessionId) public returns (uint) {
        BattleSession storage session = sessions[sessionId];
        bytes32 claimId = session.claimId;
        if (
            session.lastActionChallenger > session.lastActionClaimant &&
            block.timestamp > session.lastActionTimestamp + superblockTimeout
        ) {
            claimantConvicted(sessionId, session.claimant, claimId);
            return ERR_SUPERBLOCK_OK;
        } else if (
            session.lastActionClaimant > session.lastActionChallenger &&
            block.timestamp > session.lastActionTimestamp + superblockTimeout
        ) {
            challengerConvicted(sessionId, session.challenger, claimId);
            return ERR_SUPERBLOCK_OK;
        } else {
            emit SessionError(sessionId, ERR_SUPERBLOCK_NO_TIMEOUT);
            return ERR_SUPERBLOCK_NO_TIMEOUT;
        }
    }

    // @dev - To be called when a battle sessions  was decided
    function sessionDecided(bytes32 sessionId, bytes32 claimId, address winner, address loser) internal;

    // @dev - To be called when a challenger is convicted
    function challengerConvicted(bytes32 sessionId, address challenger, bytes32 claimId) internal {
        BattleSession storage session = sessions[sessionId];
        sessionDecided(sessionId, claimId, session.claimant, session.challenger);
        disable(sessionId);
        emit ChallengerConvicted(sessionId, challenger);
    }

    // @dev - To be called when a submitter is convicted
    function claimantConvicted(bytes32 sessionId, address claimant, bytes32 claimId) internal {
        BattleSession storage session = sessions[sessionId];
        sessionDecided(sessionId, claimId, session.challenger, session.claimant);
        disable(sessionId);
        emit ClaimantConvicted(sessionId, claimant);
    }

    // @dev - Disable session
    // It should be called only when either the submitter or the challenger were convicted.
    function disable(bytes32 sessionId) internal {
        delete sessions[sessionId];
    }
}

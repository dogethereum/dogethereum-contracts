pragma solidity ^0.4.19;

import {DogeErrorCodes} from "./DogeErrorCodes.sol";


// @dev - Manages a battle session between superblock submitter and challenger
contract DogeBattleManager is DogeErrorCodes {

    event NewSession(bytes32 sessionId, address claimant, address challenger);
    event ChallengerConvicted(bytes32 sessionId, address challenger);
    event ClaimantConvicted(bytes32 sessionId, address claimant);

    event QueryMerkleRootHashes(bytes32 sessionId, address claimant);
    event RespondMerkleRootHashes(bytes32 sessionId, address challenger, bytes data);
    event QueryBlockHeader(bytes32 sessionId, address claimant, bytes32 blockHash);
    event RespondBlockHeader(bytes32 sessionId, address challenger, bytes data);

    event SessionError(bytes32 sessionId, uint err);

    uint constant responseTimeout = 5;  // @dev - In blocks

    struct BattleSession {
        bytes32 id;
        bytes32 claimId;
        address claimant;
        address challenger;
        uint lastClaimantMessage;
        uint lastChallengerMessage;
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

    // @dev - Start a battle session
    function beginBattleSession(bytes32 claimId, address challenger, address claimant) public returns (bytes32) {
        bytes32 sessionId = keccak256(abi.encode(claimId, msg.sender, sessionsCount));
        BattleSession storage session = sessions[sessionId];
        session.id = sessionId;
        session.claimId = claimId;
        session.claimant = claimant;
        session.challenger = challenger;
        session.lastClaimantMessage = block.number;
        session.lastChallengerMessage = block.number;

        sessionsCount += 1;

        emit NewSession(sessionId, claimant, challenger);
        return sessionId;
    }

    // @dev - Challenger makes a query for superblock hashes
    function queryMerkleRootHashes(bytes32 claimId) internal returns (bool);

    // @dev - Challenger makes a query for block header data for a hash
    function queryBlockHeader(bytes32 claimId, bytes32 blockHash) internal returns (bool);

    // @dev - For the challenger to start a query
    function query(bytes32 sessionId, uint step, bytes32 data) onlyChallenger(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        bytes32 claimId = session.claimId;
        bool succeeded = false;
        if (step == 0) {
            succeeded = queryMerkleRootHashes(claimId);
            emit QueryMerkleRootHashes(sessionId, session.claimant);
        } else if (step == 1) {
            succeeded = queryBlockHeader(claimId, data);
            emit QueryBlockHeader(sessionId, session.claimant, data);
        }

        if (succeeded) {
            session.lastChallengerMessage = block.number;
        }
    }

    // @dev - Submitter send hashes to verify superblock merkle root
    function verifyMerkleRootHashes(bytes32 claimId, bytes data) internal returns (bool);

    // @dev - Verify block header send by challenger
    function verifyBlockHeader(bytes32 claimId, bytes data) internal returns (bool);

    // @dev - For the submitter to respond to challenger queries
    function respond(bytes32 sessionId, uint step, bytes data) onlyClaimant(sessionId) public {
        BattleSession storage session = sessions[sessionId];
        bytes32 claimId = session.claimId;
        bool succeeded = false;
        if (step == 0) {
            succeeded = verifyMerkleRootHashes(claimId, data);
            emit RespondMerkleRootHashes(sessionId, session.challenger, data);
        } else if (step == 1) {
            succeeded = verifyBlockHeader(claimId, data);
            emit RespondBlockHeader(sessionId, session.challenger, data);
        }

        if (succeeded) {
            session.lastClaimantMessage = block.number;
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
            session.lastChallengerMessage > session.lastClaimantMessage &&
            block.number> session.lastChallengerMessage + responseTimeout
        ) {
            claimantConvicted(sessionId, session.claimant, claimId);
            return ERR_SUPERBLOCK_OK;
        } else if (
            session.lastClaimantMessage >= session.lastChallengerMessage &&
            block.number > session.lastClaimantMessage + responseTimeout
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

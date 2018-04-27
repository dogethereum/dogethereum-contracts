pragma solidity ^0.4.19;


// @dev - Manages a battle session between superblock submitter and challenger
contract BattleManager {

    event NewSession(bytes32 sessionId, address claimant, address challenger);
    event NewQuery(bytes32 sessionId, address claimant, uint step);
    event NewResponse(bytes32 sessionId, address challenger);
    event ChallengerConvicted(bytes32 sessionId, address challenger);
    event ClaimantConvicted(bytes32 sessionId, address claimant);

    uint constant responseTime = 1 hours;

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

    uint sessionsCount = 0;

    // @dev - Start a battle session
    function beginBattleSession(bytes32 claimId, address challenger, address claimant) public returns (bytes32) {
        bytes32 sessionId = bytes32(sessionsCount+1);
        BattleSession storage s = sessions[sessionId];
        s.id = sessionId;
        s.claimId = claimId;
        s.claimant = claimant;
        s.challenger = challenger;
        s.lastClaimantMessage = now;
        s.lastChallengerMessage = now;

        sessionsCount+=1;

        emit NewSession(sessionId, claimant, challenger);
        return sessionId;
    }

    // @dev - Challenger makes a query for superblock hashes
    function queryHashes(bytes32 claimId) internal;

    // @dev - Challenger makes a query for block header data for a hash
    function queryBlockHeader(bytes32 claimId, bytes32 blockHash) internal;

    // @dev - For the challenger to start a query
    function query(bytes32 sessionId, uint step, bytes32 data) onlyChallenger(sessionId) public {
        BattleSession storage s = sessions[sessionId];
        bytes32 claimId = s.claimId;
        if (step == 0) {
            queryHashes(claimId);
        } else if (step == 1) {
            queryBlockHeader(claimId, data);
        }

        s.lastChallengerMessage = now;
        emit NewQuery(sessionId, s.claimant, step);
    }

    // @dev - Submitter send hashes to verify superblock merkle root
    function verifyHashes(bytes32 claimId, bytes data) internal;

    // @dev - Verify block header send by challenger
    function verifyBlockHeader(bytes32 claimId, bytes data) internal;

    // @dev - For the submitter to respond to challenger queries
    function respond(bytes32 sessionId, uint step, bytes data) onlyClaimant(sessionId) public {
        BattleSession storage s = sessions[sessionId];
        bytes32 claimId = s.claimId;
        if (step == 0) {
            verifyHashes(claimId, data);
        } else if (step == 1) {
            verifyBlockHeader(claimId, data);
        }

        s.lastClaimantMessage = now;
        emit NewResponse(sessionId, s.challenger);
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
    function timeout(bytes32 sessionId, bytes32 claimId) public {
        BattleSession storage session = sessions[sessionId];
        require(session.claimant != 0);
        if (
            session.lastChallengerMessage > session.lastClaimantMessage &&
            now > session.lastChallengerMessage + responseTime
        ) {
            claimantConvicted(sessionId, session.claimant, claimId);
        } else if (
            session.lastClaimantMessage > session.lastChallengerMessage &&
            now > session.lastClaimantMessage + responseTime
        ) {
            challengerConvicted(sessionId, session.challenger, claimId);
        } else {
            require(false);
        }
    }

    // @dev - To be called when a battle sessions  was decided
    function sessionDecided(bytes32 sessionId, bytes32 claimId, address winner, address loser) internal;

    // @dev - To be called when a challenger is convicted
    function challengerConvicted(bytes32 sessionId, address challenger, bytes32 claimId) internal {
        BattleSession storage s = sessions[sessionId];
        sessionDecided(sessionId, claimId, s.claimant, s.challenger);
        disable(sessionId);
        emit ChallengerConvicted(sessionId, challenger);
    }

    // @dev - To be called when a submitter is convicted
    function claimantConvicted(bytes32 sessionId, address claimant, bytes32 claimId) internal {
        BattleSession storage s = sessions[sessionId];
        sessionDecided(sessionId, claimId, s.challenger, s.claimant);
        disable(sessionId);
        emit ClaimantConvicted(sessionId, claimant);
    }

    // @dev - Disable session
    // It should be called only when either the submitter or the challenger were convicted.
    function disable(bytes32 sessionId) internal {
        delete sessions[sessionId];
    }
}

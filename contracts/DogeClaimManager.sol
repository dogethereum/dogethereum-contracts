pragma solidity ^0.4.19;

import {DogeDepositsManager} from './DogeDepositsManager.sol';
import {DogeSuperblocks} from './DogeSuperblocks.sol';
import {DogeBattleManager} from './DogeBattleManager.sol';
import {DogeTx} from './DogeParser/DogeTx.sol';
import {DogeErrorCodes} from "./DogeErrorCodes.sol";

// @dev - Manager of superblock claims
//
// Manages superblocks proposal and challenges
contract DogeClaimManager is DogeDepositsManager, DogeBattleManager {

    struct SuperblockClaim {
        bytes32 superblockId;                       // Superblock Id
        address claimant;                           // Superblock submitter
        uint createdAt;                             // Superblock creation time

        address[] challengers;                      // List of challengers
        mapping (address => uint) bondedDeposits;   // Deposit associated to challengers

        uint currentChallenger;                     // Index of challenger in current session
        mapping (address => bytes32) sessions;      // Challenge sessions

        uint challengeTimeout;                      // Claim timeout

        bool verificationOngoing;                   // Challenge session has started

        bool decided;                               // If the claim was decided
        bool invalid;                               // If superblock is invalid
    }

    // Active Superblock claims
    mapping (bytes32 => SuperblockClaim) public claims;

    // Superblocks contract
    DogeSuperblocks public superblocks;

    // Confirmations required to confirm semi approved superblocks
    uint public superblockConfirmations;

    event DepositBonded(bytes32 claimId, address account, uint amount);
    event DepositUnbonded(bytes32 claimId, address account, uint amount);
    event SuperblockClaimCreated(bytes32 claimId, address claimant, bytes32 superblockId);
    event SuperblockClaimChallenged(bytes32 claimId, address challenger);
    event SuperblockBattleDecided(bytes32 sessionId, address winner, address loser);
    event SuperblockClaimSuccessful(bytes32 claimId, address claimant, bytes32 superblockId);
    event SuperblockClaimPending(bytes32 claimId, address claimant, bytes32 superblockId);
    event SuperblockClaimFailed(bytes32 claimId, address claimant, bytes32 superblockId);
    event VerificationGameStarted(bytes32 claimId, address claimant, address challenger, bytes32 sessionId);

    event ErrorClaim(bytes32 claimId, uint err);

    // @dev – Configures the contract storing the superblocks
    // @param _network Network type to use for block difficulty validation
    // @param _superblocks Contract that manages superblocks
    // @param _superblockDuration Superblock duration (in seconds)
    // @param _superblockDelay Delay to accept a superblock submition (in seconds)
    // @param _superblockTimeout Time to wait for challenges (in seconds)
    // @param _superblockConfirmations Confirmations required to confirm semi approved superblocks
    constructor(Network _network, DogeSuperblocks _superblocks, uint _superblockDuration, uint _superblockDelay, uint _superblockTimeout, uint _superblockConfirmations)
        DogeBattleManager(_network, _superblockDuration, _superblockDelay, _superblockTimeout) public {
        superblocks = _superblocks;
        superblockConfirmations = _superblockConfirmations;
    }

    // @dev – locks up part of the a user's deposit into a claim.
    // @param claimId – the claim id.
    // @param account – the user's address.
    // @param amount – the amount of deposit to lock up.
    // @return – the user's deposit bonded for the claim.
    function bondDeposit(bytes32 claimId, address account, uint amount) internal returns (uint, uint) {
        SuperblockClaim storage claim = claims[claimId];

        if (!claimExists(claim)) {
            return (ERR_SUPERBLOCK_BAD_CLAIM, 0);
        }

        if (deposits[account] < amount) {
            return (ERR_SUPERBLOCK_MIN_DEPOSIT, deposits[account]);
        }

        deposits[account] -= amount;
        claim.bondedDeposits[account] += amount;
        emit DepositBonded(claimId, account, amount);

        return (ERR_SUPERBLOCK_OK, claim.bondedDeposits[account]);
    }

    // @dev – accessor for a claims bonded deposits.
    // @param claimId – the claim id.
    // @param account – the user's address.
    // @return – the user's deposit bonded for the claim.
    function getBondedDeposit(bytes32 claimId, address account) public view returns (uint) {
        SuperblockClaim storage claim = claims[claimId];
        require(claimExists(claim));
        return claim.bondedDeposits[account];
    }

    // @dev – unlocks a user's bonded deposits from a claim.
    // @param claimId – the claim id.
    // @param account – the user's address.
    // @return – the user's deposit which was unbonded from the claim.
    function unbondDeposit(bytes32 claimId, address account) internal returns (uint, uint) {
        SuperblockClaim storage claim = claims[claimId];
        if (!claimExists(claim)) {
            return (ERR_SUPERBLOCK_BAD_CLAIM, 0);
        }
        if (!claim.decided) {
            return (ERR_SUPERBLOCK_BAD_STATUS, 0);
        }

        uint bondedDeposit = claim.bondedDeposits[account];

        delete claim.bondedDeposits[account];
        deposits[account] += bondedDeposit;

        emit DepositUnbonded(claimId, account, bondedDeposit);

        return (ERR_SUPERBLOCK_OK, bondedDeposit);
    }

    // @dev – Propose a new superblock.
    //
    // @param _blocksMerkleRoot Root of the merkle tree of blocks contained in a superblock
    // @param _accumulatedWork Accumulated proof of work of the last block in the superblock
    // @param _timestamp Timestamp of the last block in the superblock
    // @param _prevTimestamp Timestamp of the block previous to the last
    // @param _lastHash Hash of the last block in the superblock
    // @param _lastBits Difficulty bits of the last block in the superblock
    // @param _parentId Id of the parent superblock
    // @return Error code and superblockId
    function proposeSuperblock(bytes32 _blocksMerkleRoot, uint _accumulatedWork, uint _timestamp, uint _prevTimestamp, bytes32 _lastHash, uint32 _lastBits, bytes32 _parentHash) public returns (uint, bytes32) {
        require(address(superblocks) != 0);

        if (deposits[msg.sender] < minDeposit) {
            emit ErrorClaim(0, ERR_SUPERBLOCK_MIN_DEPOSIT);
            return (ERR_SUPERBLOCK_MIN_DEPOSIT, 0);
        }

        if (_timestamp + superblockDelay > block.timestamp) {
            emit ErrorClaim(0, ERR_SUPERBLOCK_BAD_TIMESTAMP);
            return (ERR_SUPERBLOCK_BAD_TIMESTAMP, 0);
        }

        uint err;
        bytes32 superblockId;
        (err, superblockId) = superblocks.propose(_blocksMerkleRoot, _accumulatedWork, _timestamp, _prevTimestamp, _lastHash, _lastBits, _parentHash, msg.sender);
        if (err != 0) {
            emit ErrorClaim(superblockId, err);
            return (err, superblockId);
        }

        bytes32 claimId = superblockId;
        SuperblockClaim storage claim = claims[claimId];
        if (claimExists(claim)) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_BAD_CLAIM);
            return (ERR_SUPERBLOCK_BAD_CLAIM, claimId);
        }

        claim.superblockId = superblockId;
        claim.claimant = msg.sender;
        claim.currentChallenger = 0;
        claim.decided = false;
        claim.invalid = false;
        claim.verificationOngoing = false;
        claim.createdAt = block.timestamp;
        claim.challengeTimeout = block.timestamp + superblockTimeout;

        (err, ) = bondDeposit(claimId, msg.sender, minDeposit);
        assert(err == ERR_SUPERBLOCK_OK);

        emit SuperblockClaimCreated(claimId, msg.sender, superblockId);

        return (ERR_SUPERBLOCK_OK, superblockId);
    }

    // @dev – challenge a superblock claim.
    // @param superblockId – Id of the superblock to challenge.
    // @return Error code an claim Id
    function challengeSuperblock(bytes32 superblockId) public returns (uint, bytes32) {
        require(address(superblocks) != 0);

        bytes32 claimId = superblockId;
        SuperblockClaim storage claim = claims[claimId];

        if (!claimExists(claim)) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_BAD_CLAIM);
            return (ERR_SUPERBLOCK_BAD_CLAIM, claimId);
        }
        if (claim.decided) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_CLAIM_DECIDED);
            return (ERR_SUPERBLOCK_CLAIM_DECIDED, claimId);
        }
        if (deposits[msg.sender] < minDeposit) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_MIN_DEPOSIT);
            return (ERR_SUPERBLOCK_MIN_DEPOSIT, claimId);
        }

        uint err;
        (err, ) = superblocks.challenge(superblockId, msg.sender);
        if (err != 0) {
            emit ErrorClaim(claimId, err);
            return (err, 0);
        }

        (err, ) = bondDeposit(claimId, msg.sender, minDeposit);
        assert(err == ERR_SUPERBLOCK_OK);

        claim.challengeTimeout = block.timestamp + superblockTimeout;
        claim.challengers.push(msg.sender);
        emit SuperblockClaimChallenged(claimId, msg.sender);

        if (!claim.verificationOngoing) {
            runNextBattleSession(claimId);
        }

        return (ERR_SUPERBLOCK_OK, claimId);
    }

    // @dev – runs the battle session to verify a superblock for the next challenger
    // @param claimId – the claim id.
    function runNextBattleSession(bytes32 claimId) internal returns (bool) {
        SuperblockClaim storage claim = claims[claimId];

        if (!claimExists(claim)) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_BAD_CLAIM);
            return false;
        }

        // superblock marked as invalid do not have to run remaining challengers
        if (claim.decided || claim.invalid) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_CLAIM_DECIDED);
            return false;
        }

        if (claim.verificationOngoing) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_VERIFICATION_PENDING);
            return false;
        }

        if (claim.currentChallenger < claim.challengers.length) {

            bytes32 sessionId = beginBattleSession(claimId, claim.claimant, claim.challengers[claim.currentChallenger]);

            claim.sessions[claim.challengers[claim.currentChallenger]] = sessionId;
            emit VerificationGameStarted(claimId, claim.claimant, claim.challengers[claim.currentChallenger], sessionId);

            claim.verificationOngoing = true;
            claim.currentChallenger += 1;
        }

        return true;
    }

    // @dev – check whether a claim has successfully withstood all challenges.
    // if successful without challenges it will mark the superblock as confirmed.
    // if successful with more that one challenge it will mark the superblock as semi-approved.
    // if verification failed it will mark the superblock as invalid.
    //
    // @param claimId – the claim ID.
    function checkClaimFinished(bytes32 claimId) public returns (bool) {
        SuperblockClaim storage claim = claims[claimId];

        if (!claimExists(claim)) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_BAD_CLAIM);
            return false;
        }

        // check that there is no ongoing verification game.
        if (claim.verificationOngoing) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_VERIFICATION_PENDING);
            return false;
        }

        // an invalid superblock can be rejected immediately
        if (claim.invalid) {
            // The superblock is invalid, submitter abandoned
            // or superblock data is inconsistent
            claim.decided = true;
            superblocks.invalidate(claim.superblockId, msg.sender);
            emit SuperblockClaimFailed(claimId, claim.claimant, claim.superblockId);
            doPayChallengers(claimId, claim);
            return false;
        }

        // check that the claim has exceeded the claim's specific challenge timeout.
        if (block.timestamp <= claim.challengeTimeout) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_NO_TIMEOUT);
            return false;
        }

        // check that all verification games have been played.
        if (claim.currentChallenger < claim.challengers.length) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_VERIFICATION_PENDING);
            return false;
        }

        claim.decided = true;

        bool confirmImmediately = false;
        // No challengers and parent approved confirm immediately
        if (claim.challengers.length == 0) {
            bytes32 parentId = superblocks.getSuperblockParentId(claim.superblockId);
            DogeSuperblocks.Status status = superblocks.getSuperblockStatus(parentId);
            if (status == DogeSuperblocks.Status.Approved) {
                confirmImmediately = true;
            }
        }

        if (confirmImmediately) {
            superblocks.confirm(claim.superblockId, msg.sender);
            unbondDeposit(claimId, claim.claimant);
            emit SuperblockClaimSuccessful(claimId, claim.claimant, claim.superblockId);
        } else {
            superblocks.semiApprove(claim.superblockId, msg.sender);
            emit SuperblockClaimPending(claimId, claim.claimant, claim.superblockId);
        }
        return true;
    }

    // @dev – confirm semi approved superblock.
    //
    // @param claimId – the claim ID.
    function confirmClaim(bytes32 claimId, bytes32 descendantId) public returns (bool) {
        uint i = 0;
        bytes32 id = descendantId;
        DogeSuperblocks.Status status;
        SuperblockClaim storage claim = claims[id];
        while (true) {
            if (!claimExists(claim)) {
                emit ErrorClaim(id, ERR_SUPERBLOCK_BAD_CLAIM);
                return false;
            }

            status = superblocks.getSuperblockStatus(id);
            if (status != DogeSuperblocks.Status.SemiApproved) {
                emit ErrorClaim(id, ERR_SUPERBLOCK_BAD_STATUS);
                return false;
            }

            if (id == claimId) {
                break;
            }

            id = superblocks.getSuperblockParentId(id);
            i += 1;
            claim = claims[id];
        }

        if (i < superblockConfirmations) {
            emit ErrorClaim(id, ERR_SUPERBLOCK_MISSING_CONFIRMATIONS);
            return false;
        }

        bytes32 parentId = superblocks.getSuperblockParentId(claimId);
        status = superblocks.getSuperblockStatus(parentId);
        if (status == DogeSuperblocks.Status.Approved) {
            superblocks.confirm(claimId, msg.sender);
            emit SuperblockClaimSuccessful(claimId, claim.claimant, claim.superblockId);
            doPaySubmitter(claimId, claim);
            unbondDeposit(claimId, claim.claimant);
            return true;
        }

        return false;
    }

    // @dev – confirm semi approved superblock.
    //
    // @param claimId – the claim ID.
    function rejectClaim(bytes32 claimId) public returns (bool) {
        SuperblockClaim storage claim = claims[claimId];
        if (!claimExists(claim)) {
            emit ErrorClaim(id, ERR_SUPERBLOCK_BAD_CLAIM);
            return false;
        }

        uint height = superblocks.getSuperblockHeight(claimId);
        bytes32 id = superblocks.getBestSuperblock();
        if (superblocks.getSuperblockHeight(id) < height + superblockConfirmations) {
            emit ErrorClaim(id, ERR_SUPERBLOCK_MISSING_CONFIRMATIONS);
            return false;
        }

        while (superblocks.getSuperblockHeight(id) > height) {
            id = superblocks.getSuperblockParentId(id);
        }

        if (id != claimId) {
            emit SuperblockClaimFailed(claimId, claim.claimant, claim.superblockId);
            doPayChallengers(claimId, claim);
        }

        return false;
    }

    // @dev – called when a battle session has ended.
    //
    // @param sessionId – the sessionId.
    // @param claimId - Id of the superblock claim
    // @param winner – winner of the verification game.
    // @param loser – loser of the verification game.
    function sessionDecided(bytes32 sessionId, bytes32 claimId, address winner, address loser) internal {
        SuperblockClaim storage claim = claims[claimId];

        require(claimExists(claim));

        claim.verificationOngoing = false;

        if (claim.claimant == loser) {
            // the claim is over.
            // Trigger end of verification game
            claim.invalid = true;
        } else if (claim.claimant == winner) {
            // the claim continues.
            // It should not fail when called from sessionDecided
            runNextBattleSession(claimId);
        } else {
            revert();
        }

        emit SuperblockBattleDecided(sessionId, winner, loser);
    }

    // @dev - Pay challengers than run their challenge with submitter deposits
    // Challengers that do not run will be returned their deposits
    function doPayChallengers(bytes32 claimId, SuperblockClaim storage claim) internal {
        uint rewards = claim.bondedDeposits[claim.claimant];
        claim.bondedDeposits[claim.claimant] = 0;
        uint totalDeposits = 0;
        uint idx = 0;
        for (idx=0; idx<claim.currentChallenger; ++idx) {
            totalDeposits += claim.bondedDeposits[claim.challengers[idx]];
        }
        address challenger;
        uint reward;
        for (idx=0; idx<claim.currentChallenger; ++idx) {
            challenger = claim.challengers[idx];
            reward = rewards * claim.bondedDeposits[challenger] / totalDeposits;
            claim.bondedDeposits[challenger] += reward;
        }
        uint bondedDeposit;
        for (idx=0; idx<claim.challengers.length; ++idx) {
            challenger = claim.challengers[idx];
            bondedDeposit = claim.bondedDeposits[challenger];
            deposits[challenger] += bondedDeposit;
            claim.bondedDeposits[challenger] = 0;
            emit DepositUnbonded(claimId, challenger, bondedDeposit);
        }
    }

    // @dev - Pay submitter with challenger deposits
    function doPaySubmitter(bytes32 claimId, SuperblockClaim storage claim) internal {
        address challenger;
        uint bondedDeposit;
        for (uint idx=0; idx<claim.challengers.length; ++idx) {
            challenger = claim.challengers[idx];
            bondedDeposit = claim.bondedDeposits[challenger];
            claim.bondedDeposits[challenger] = 0;
            claim.bondedDeposits[claim.claimant] += bondedDeposit;
        }
        unbondDeposit(claimId, claim.claimant);
    }

    // @dev - Check if a superblock can be semi approved by calling checkClaimFinished
    function getInBattleAndSemiApprovable(bytes32 superblockId) public view returns (bool) {
        SuperblockClaim storage claim = claims[superblockId];
        return (superblocks.getSuperblockStatus(superblockId) == DogeSuperblocks.Status.InBattle &&
            !claim.invalid && !claim.verificationOngoing && block.timestamp > claim.challengeTimeout
            && claim.currentChallenger >= claim.challengers.length);
    }

    // @dev – Check if a claim exists
    function claimExists(SuperblockClaim claim) pure private returns(bool) {
        return (claim.claimant != 0x0);
    }

    // @dev - Return superblock submission timestamp
    function getNewSuperblockEventTimestamp(bytes32 superblockId) public view returns (uint) {
        return claims[superblockId].createdAt;
    }

    // @dev - Return whether or not a claim has already been made
    function getClaimExists(bytes32 superblockId) public view returns (bool) {
        return claimExists(claims[superblockId]);
    }

    // @dev - Return claim status
    function getClaimDecided(bytes32 superblockId) public view returns (bool) {
        return claims[superblockId].decided;
    }

    // @dev - Check if a claim is invalid
    function getClaimInvalid(bytes32 superblockId) public view returns (bool) {
        // TODO: see if this is redundant with superblock status
        return claims[superblockId].invalid;
    }

    // @dev - Check if a claim has a verification game in progress
    function getClaimVerificationOngoing(bytes32 superblockId) public view returns (bool) {
        return claims[superblockId].verificationOngoing;
    }

    // @dev - Returns timestamp of challenge timeout
    function getClaimChallengeTimeout(bytes32 superblockId) public view returns (uint) {
        return claims[superblockId].challengeTimeout;
    }

    // @dev - Return the number of challengers whose battles haven't been decided yet
    function getClaimRemainingChallengers(bytes32 superblockId) public view returns (uint) {
        SuperblockClaim storage claim = claims[superblockId];
        return claim.challengers.length - claim.currentChallenger;
    }

    // @dev – Return session by challenger
    function getSession(bytes32 claimId, address challenger) public view returns(bytes32) {
        return claims[claimId].sessions[challenger];
    }

    function getClaimChallengers(bytes32 superblockId) public view returns (address[]) {
        SuperblockClaim storage claim = claims[superblockId];
        return claim.challengers;
    }

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
    ) {
        return superblocks.getSuperblock(superblockId);
    }
}

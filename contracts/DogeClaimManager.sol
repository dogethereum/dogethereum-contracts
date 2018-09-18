pragma solidity ^0.4.19;

import {DogeDepositsManager} from './DogeDepositsManager.sol';
import {DogeSuperblocks} from './DogeSuperblocks.sol';
import {DogeBattleManager} from './DogeBattleManager.sol';
import {DogeTx} from './DogeParser/DogeTx.sol';
import {DogeErrorCodes} from "./DogeErrorCodes.sol";

// @dev - Manager of superblock claims
//
// Manages superblocks proposal and challenges
contract DogeClaimManager is DogeDepositsManager, DogeErrorCodes {

    struct SuperblockClaim {
        bytes32 superblockHash;                       // Superblock Id
        address submitter;                           // Superblock submitter
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

    // Superblocks contract
    DogeBattleManager public dogeBattleManager;

    // Confirmations required to confirm semi approved superblocks
    uint public superblockConfirmations;

    // Minimum deposit required to start/continue challenge
    uint public minDeposit = 1;

    uint public superblockDelay;            // Delay required to submit superblocks (in seconds)
    uint public superblockTimeout;          // Timeout action (in seconds)

    event DepositBonded(bytes32 claimId, address account, uint amount);
    event DepositUnbonded(bytes32 claimId, address account, uint amount);
    event SuperblockClaimCreated(bytes32 claimId, address submitter, bytes32 superblockHash);
    event SuperblockClaimChallenged(bytes32 claimId, address challenger);
    event SuperblockBattleDecided(bytes32 sessionId, address winner, address loser);
    event SuperblockClaimSuccessful(bytes32 claimId, address submitter, bytes32 superblockHash);
    event SuperblockClaimPending(bytes32 claimId, address submitter, bytes32 superblockHash);
    event SuperblockClaimFailed(bytes32 claimId, address submitter, bytes32 superblockHash);
    event VerificationGameStarted(bytes32 claimId, address submitter, address challenger, bytes32 sessionId);

    event ErrorClaim(bytes32 claimId, uint err);

    modifier onlyBattleManager() {
        require(msg.sender == address(dogeBattleManager));
        _;
    }

    modifier onlyMeOrBattleManager() {
        require(msg.sender == address(dogeBattleManager) || msg.sender == address(this));
        _;
    }

    // @dev – Configures the contract managing superblocks challenges
    // @param _superblocks Contract that manages superblocks
    // @param _battleManager Contract that manages battles
    // @param _superblockDelay Delay to accept a superblock submition (in seconds)
    // @param _superblockTimeout Time to wait for challenges (in seconds)
    // @param _superblockConfirmations Confirmations required to confirm semi approved superblocks
    constructor(
        DogeSuperblocks _superblocks,
        DogeBattleManager _dogeBattleManager,
        uint _superblockDelay,
        uint _superblockTimeout,
        uint _superblockConfirmations
    ) public {
        superblocks = _superblocks;
        dogeBattleManager = _dogeBattleManager;
        superblockDelay = _superblockDelay;
        superblockTimeout = _superblockTimeout;
        superblockConfirmations = _superblockConfirmations;
    }

    // @dev – locks up part of the a user's deposit into a claim.
    // @param claimId – the claim id.
    // @param account – the user's address.
    // @param amount – the amount of deposit to lock up.
    // @return – the user's deposit bonded for the claim.
    function bondDeposit(bytes32 claimId, address account, uint amount) onlyMeOrBattleManager external returns (uint, uint) {
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
    // @param _parentHash Id of the parent superblock
    // @return Error code and superblockHash
    function proposeSuperblock(
        bytes32 _blocksMerkleRoot,
        uint _accumulatedWork,
        uint _timestamp,
        uint _prevTimestamp,
        bytes32 _lastHash,
        uint32 _lastBits,
        bytes32 _parentHash
    ) public returns (uint, bytes32) {
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
        bytes32 superblockHash;
        (err, superblockHash) = superblocks.propose(_blocksMerkleRoot, _accumulatedWork, _timestamp, _prevTimestamp, _lastHash, _lastBits, _parentHash, msg.sender);
        if (err != 0) {
            emit ErrorClaim(superblockHash, err);
            return (err, superblockHash);
        }

        bytes32 claimId = superblockHash;
        SuperblockClaim storage claim = claims[claimId];
        if (claimExists(claim)) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_BAD_CLAIM);
            return (ERR_SUPERBLOCK_BAD_CLAIM, claimId);
        }

        claim.superblockHash = superblockHash;
        claim.submitter = msg.sender;
        claim.currentChallenger = 0;
        claim.decided = false;
        claim.invalid = false;
        claim.verificationOngoing = false;
        claim.createdAt = block.timestamp;
        claim.challengeTimeout = block.timestamp + superblockTimeout;

        (err, ) = this.bondDeposit(claimId, msg.sender, minDeposit);
        assert(err == ERR_SUPERBLOCK_OK);

        emit SuperblockClaimCreated(claimId, msg.sender, superblockHash);

        return (ERR_SUPERBLOCK_OK, superblockHash);
    }

    // @dev – challenge a superblock claim.
    // @param superblockHash – Id of the superblock to challenge.
    // @return Error code an claim Id
    function challengeSuperblock(bytes32 superblockHash) public returns (uint, bytes32) {
        require(address(superblocks) != 0);

        bytes32 claimId = superblockHash;
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
        (err, ) = superblocks.challenge(superblockHash, msg.sender);
        if (err != 0) {
            emit ErrorClaim(claimId, err);
            return (err, 0);
        }

        (err, ) = this.bondDeposit(claimId, msg.sender, minDeposit);
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

            bytes32 sessionId = dogeBattleManager.beginBattleSession(claimId, claim.submitter, claim.challengers[claim.currentChallenger]);

            claim.sessions[claim.challengers[claim.currentChallenger]] = sessionId;
            emit VerificationGameStarted(claimId, claim.submitter, claim.challengers[claim.currentChallenger], sessionId);

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
            superblocks.invalidate(claim.superblockHash, msg.sender);
            emit SuperblockClaimFailed(claimId, claim.submitter, claim.superblockHash);
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
            bytes32 parentId = superblocks.getSuperblockParentId(claim.superblockHash);
            DogeSuperblocks.Status status = superblocks.getSuperblockStatus(parentId);
            if (status == DogeSuperblocks.Status.Approved) {
                confirmImmediately = true;
            }
        }

        if (confirmImmediately) {
            superblocks.confirm(claim.superblockHash, msg.sender);
            unbondDeposit(claimId, claim.submitter);
            emit SuperblockClaimSuccessful(claimId, claim.submitter, claim.superblockHash);
        } else {
            superblocks.semiApprove(claim.superblockHash, msg.sender);
            emit SuperblockClaimPending(claimId, claim.submitter, claim.superblockHash);
        }
        return true;
    }

    // @dev – confirm semi approved superblock.
    //
    // A semi approved superblock can be confirmed if it has several descendant
    // superblocks that are also semi-approved.
    // If none of the descendants were challenged they will also be confirmed.
    //
    // @param claimId – the claim ID.
    // @param descendantId - claim ID descendants
    function confirmClaim(bytes32 claimId, bytes32 descendantId) public returns (bool) {
        uint numSuperblocks = 0;
        bool confirmDescendants = true;
        bytes32 id = descendantId;
        SuperblockClaim storage claim = claims[id];
        while (id != claimId) {
            if (!claimExists(claim)) {
                emit ErrorClaim(claimId, ERR_SUPERBLOCK_BAD_CLAIM);
                return false;
            }
            if (superblocks.getSuperblockStatus(id) != DogeSuperblocks.Status.SemiApproved) {
                emit ErrorClaim(claimId, ERR_SUPERBLOCK_BAD_STATUS);
                return false;
            }
            if (confirmDescendants && claim.challengers.length > 0) {
                confirmDescendants = false;
            }
            id = superblocks.getSuperblockParentId(id);
            claim = claims[id];
            numSuperblocks += 1;
        }

        if (numSuperblocks < superblockConfirmations) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_MISSING_CONFIRMATIONS);
            return false;
        }
        if (superblocks.getSuperblockStatus(id) != DogeSuperblocks.Status.SemiApproved) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_BAD_STATUS);
            return false;
        }

        bytes32 parentId = superblocks.getSuperblockParentId(claimId);
        if (superblocks.getSuperblockStatus(parentId) != DogeSuperblocks.Status.Approved) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_BAD_STATUS);
            return false;
        }

        (uint err, ) = superblocks.confirm(claimId, msg.sender);
        if (err != ERR_SUPERBLOCK_OK) {
            emit ErrorClaim(claimId, err);
            return false;
        }
        emit SuperblockClaimSuccessful(claimId, claim.submitter, claim.superblockHash);
        doPaySubmitter(claimId, claim);
        unbondDeposit(claimId, claim.submitter);

        if (confirmDescendants) {
            bytes32[] memory descendants = new bytes32[](numSuperblocks);
            id = descendantId;
            uint idx=0;
            while (id != claimId) {
                descendants[idx] = id;
                id = superblocks.getSuperblockParentId(id);
                idx += 1;
            }
            while (idx > 0) {
                idx -= 1;
                id = descendants[idx];
                claim = claims[id];
                (err, ) = superblocks.confirm(id, msg.sender);
                require(err == ERR_SUPERBLOCK_OK);
                emit SuperblockClaimSuccessful(id, claim.submitter, claim.superblockHash);
                doPaySubmitter(id, claim);
                unbondDeposit(id, claim.submitter);
            }
        }

        return true;
    }

    // @dev – Reject a semi approved superblock.
    //
    // Superblocks that are not in the main chain can be marked as
    // not valid.
    //
    // @param claimId – the claim ID.
    function rejectClaim(bytes32 claimId) public returns (bool) {
        SuperblockClaim storage claim = claims[claimId];
        if (!claimExists(claim)) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_BAD_CLAIM);
            return false;
        }

        uint height = superblocks.getSuperblockHeight(claimId);
        bytes32 id = superblocks.getBestSuperblock();
        if (superblocks.getSuperblockHeight(id) < height + superblockConfirmations) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_MISSING_CONFIRMATIONS);
            return false;
        }

        id = superblocks.getSuperblockAt(height);

        if (id != claimId) {
            DogeSuperblocks.Status status = superblocks.getSuperblockStatus(claimId);

            if (status != DogeSuperblocks.Status.SemiApproved) {
                emit ErrorClaim(claimId, ERR_SUPERBLOCK_BAD_STATUS);
                return false;
            }

            if (!claim.decided) {
                emit ErrorClaim(claimId, ERR_SUPERBLOCK_CLAIM_DECIDED);
                return false;
            }

            superblocks.invalidate(claimId, msg.sender);
            emit SuperblockClaimFailed(claimId, claim.submitter, claim.superblockHash);
            doPayChallengers(claimId, claim);
            return true;
        }

        return false;
    }

    // @dev – called when a battle session has ended.
    //
    // @param sessionId – the sessionId.
    // @param claimId - Id of the superblock claim
    // @param winner – winner of the verification game.
    // @param loser – loser of the verification game.
    function sessionDecided(bytes32 sessionId, bytes32 claimId, address winner, address loser) onlyBattleManager public {
        SuperblockClaim storage claim = claims[claimId];

        require(claimExists(claim));

        claim.verificationOngoing = false;

        if (claim.submitter == loser) {
            // the claim is over.
            // Trigger end of verification game
            claim.invalid = true;
        } else if (claim.submitter == winner) {
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
        uint rewards = claim.bondedDeposits[claim.submitter];
        claim.bondedDeposits[claim.submitter] = 0;
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
            claim.bondedDeposits[claim.submitter] += bondedDeposit;
        }
        unbondDeposit(claimId, claim.submitter);
    }

    // @dev - Check if a superblock can be semi approved by calling checkClaimFinished
    function getInBattleAndSemiApprovable(bytes32 superblockHash) public view returns (bool) {
        SuperblockClaim storage claim = claims[superblockHash];
        return (superblocks.getSuperblockStatus(superblockHash) == DogeSuperblocks.Status.InBattle &&
            !claim.invalid && !claim.verificationOngoing && block.timestamp > claim.challengeTimeout
            && claim.currentChallenger >= claim.challengers.length);
    }

    // @dev – Check if a claim exists
    function claimExists(SuperblockClaim claim) pure private returns (bool) {
        return (claim.submitter != 0x0);
    }

    // @dev - Return a given superblock's submitter
    function getClaimSubmitter(bytes32 superblockHash) public view returns (address) {
        return claims[superblockHash].submitter;
    }

    // @dev - Return superblock submission timestamp
    function getNewSuperblockEventTimestamp(bytes32 superblockHash) public view returns (uint) {
        return claims[superblockHash].createdAt;
    }

    // @dev - Return whether or not a claim has already been made
    function getClaimExists(bytes32 superblockHash) public view returns (bool) {
        return claimExists(claims[superblockHash]);
    }

    // @dev - Return claim status
    function getClaimDecided(bytes32 superblockHash) public view returns (bool) {
        return claims[superblockHash].decided;
    }

    // @dev - Check if a claim is invalid
    function getClaimInvalid(bytes32 superblockHash) public view returns (bool) {
        // TODO: see if this is redundant with superblock status
        return claims[superblockHash].invalid;
    }

    // @dev - Check if a claim has a verification game in progress
    function getClaimVerificationOngoing(bytes32 superblockHash) public view returns (bool) {
        return claims[superblockHash].verificationOngoing;
    }

    // @dev - Returns timestamp of challenge timeout
    function getClaimChallengeTimeout(bytes32 superblockHash) public view returns (uint) {
        return claims[superblockHash].challengeTimeout;
    }

    // @dev - Return the number of challengers whose battles haven't been decided yet
    function getClaimRemainingChallengers(bytes32 superblockHash) public view returns (uint) {
        SuperblockClaim storage claim = claims[superblockHash];
        return claim.challengers.length - claim.currentChallenger;
    }

    // @dev – Return session by challenger
    function getSession(bytes32 claimId, address challenger) public view returns(bytes32) {
        return claims[claimId].sessions[challenger];
    }

    function getClaimChallengers(bytes32 superblockHash) public view returns (address[]) {
        SuperblockClaim storage claim = claims[superblockHash];
        return claim.challengers;
    }

    function getSuperblockInfo(bytes32 superblockHash) internal view returns (
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
        return superblocks.getSuperblock(superblockHash);
    }
}

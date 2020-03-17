pragma solidity 0.5.16;

import {DogeDepositsManager} from "./DogeDepositsManager.sol";
import {DogeSuperblocks} from "./DogeSuperblocks.sol";
import {DogeBattleManager} from "./DogeBattleManager.sol";
import {DogeMessageLibrary} from "./DogeParser/DogeMessageLibrary.sol";
import {DogeErrorCodes} from "./DogeErrorCodes.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// @dev - Manager of superblock claims
//
// Manages superblocks proposal and challenges
contract DogeClaimManager is DogeDepositsManager, DogeErrorCodes {

    using SafeMath for uint;

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

    // Active superblock claims
    mapping (bytes32 => SuperblockClaim) public claims;

    // Superblocks contract
    DogeSuperblocks public trustedSuperblocks;

    // Battle manager contract
    DogeBattleManager public trustedDogeBattleManager;

    // Confirmations required to confirm semi approved superblocks
    uint public superblockConfirmations;

    // Monetary reward for opponent in case battle is lost
    uint public battleReward;

    uint public superblockDelay;    // Delay required to submit superblocks (in seconds)
    uint public superblockTimeout;  // Timeout for action (in seconds)

    event DepositBonded(bytes32 superblockHash, address account, uint amount);
    event DepositUnbonded(bytes32 superblockHash, address account, uint amount);
    event SuperblockClaimCreated(bytes32 superblockHash, address submitter);
    event SuperblockClaimChallenged(bytes32 superblockHash, address challenger);
    event SuperblockBattleDecided(bytes32 sessionId, address winner, address loser);
    event SuperblockClaimSuccessful(bytes32 superblockHash, address submitter);
    event SuperblockClaimPending(bytes32 superblockHash, address submitter);
    event SuperblockClaimFailed(bytes32 superblockHash, address submitter);
    event VerificationGameStarted(bytes32 superblockHash, address submitter, address challenger, bytes32 sessionId);

    event ErrorClaim(bytes32 superblockHash, uint err);

    modifier onlyBattleManager() {
        require(msg.sender == address(trustedDogeBattleManager));
        _;
    }

    modifier onlyMeOrBattleManager() {
        require(msg.sender == address(trustedDogeBattleManager) || msg.sender == address(this));
        _;
    }

    // @dev – Sets up the contract managing superblock challenges
    // @param _superblocks Contract that manages superblocks
    // @param _battleManager Contract that manages battles
    // @param _superblockDelay Delay to accept a superblock submission (in seconds)
    // @param _superblockTimeout Time to wait for challenges (in seconds)
    // @param _superblockConfirmations Confirmations required to confirm semi approved superblocks
    constructor(
        DogeSuperblocks _superblocks,
        DogeBattleManager _dogeBattleManager,
        uint _superblockDelay,
        uint _superblockTimeout,
        uint _superblockConfirmations,
        uint _battleReward
    ) public {
        trustedSuperblocks = _superblocks;
        trustedDogeBattleManager = _dogeBattleManager;
        superblockDelay = _superblockDelay;
        superblockTimeout = _superblockTimeout;
        superblockConfirmations = _superblockConfirmations;
        battleReward = _battleReward;
    }

    // @dev – locks up part of a user's deposit into a claim.
    // @param superblockHash – claim id.
    // @param account – user's address.
    // @param amount – amount of deposit to lock up.
    // @return – user's deposit bonded for the claim.
    function bondDeposit(bytes32 superblockHash, address account, uint amount) onlyMeOrBattleManager external returns (uint, uint) {
        SuperblockClaim storage claim = claims[superblockHash];

        if (!claimExists(claim)) {
            return (ERR_SUPERBLOCK_BAD_CLAIM, 0);
        }

        if (deposits[account] < amount) {
            return (ERR_SUPERBLOCK_MIN_DEPOSIT, deposits[account]);
        }

        deposits[account] = deposits[account].sub(amount);
        claim.bondedDeposits[account] = claim.bondedDeposits[account].add(amount);
        emit DepositBonded(superblockHash, account, amount);

        return (ERR_SUPERBLOCK_OK, claim.bondedDeposits[account]);
    }

    // @dev – accessor for a claim's bonded deposits.
    // @param superblockHash – claim id.
    // @param account – user's address.
    // @return – user's deposit bonded for the claim.
    function getBondedDeposit(bytes32 superblockHash, address account) public view returns (uint) {
        SuperblockClaim storage claim = claims[superblockHash];
        require(claimExists(claim));
        return claim.bondedDeposits[account];
    }

    function getDeposit(address account) public view returns (uint) {
        return deposits[account];
    }

    // @dev – unlocks a user's bonded deposits from a claim.
    // @param superblockHash – claim id.
    // @param account – user's address.
    // @return – user's deposit which was unbonded from the claim.
    function unbondDeposit(bytes32 superblockHash, address account) internal returns (uint, uint) {
        SuperblockClaim storage claim = claims[superblockHash];
        if (!claimExists(claim)) {
            return (ERR_SUPERBLOCK_BAD_CLAIM, 0);
        }
        if (!claim.decided) {
            return (ERR_SUPERBLOCK_BAD_STATUS, 0);
        }

        uint bondedDeposit = claim.bondedDeposits[account];

        delete claim.bondedDeposits[account];
        deposits[account] = deposits[account].add(bondedDeposit);

        emit DepositUnbonded(superblockHash, account, bondedDeposit);

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
        require(address(trustedSuperblocks) != address(0));

        if (deposits[msg.sender] < minProposalDeposit) {
            emit ErrorClaim(0, ERR_SUPERBLOCK_MIN_DEPOSIT);
            return (ERR_SUPERBLOCK_MIN_DEPOSIT, 0);
        }

        if (_timestamp + superblockDelay > block.timestamp) {
            emit ErrorClaim(0, ERR_SUPERBLOCK_BAD_TIMESTAMP);
            return (ERR_SUPERBLOCK_BAD_TIMESTAMP, 0);
        }

        uint err;
        bytes32 superblockHash;
        (err, superblockHash) = trustedSuperblocks.propose(_blocksMerkleRoot, _accumulatedWork,
            _timestamp, _prevTimestamp, _lastHash, _lastBits, _parentHash, msg.sender);
        if (err != 0) {
            emit ErrorClaim(superblockHash, err);
            return (err, superblockHash);
        }

        SuperblockClaim storage claim = claims[superblockHash];
        if (claimExists(claim)) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_BAD_CLAIM);
            return (ERR_SUPERBLOCK_BAD_CLAIM, superblockHash);
        }

        claim.superblockHash = superblockHash;
        claim.submitter = msg.sender;
        claim.currentChallenger = 0;
        claim.decided = false;
        claim.invalid = false;
        claim.verificationOngoing = false;
        claim.createdAt = block.timestamp;
        claim.challengeTimeout = block.timestamp + superblockTimeout;

        (err, ) = this.bondDeposit(superblockHash, msg.sender, battleReward);
        assert(err == ERR_SUPERBLOCK_OK);

        emit SuperblockClaimCreated(superblockHash, msg.sender);

        return (ERR_SUPERBLOCK_OK, superblockHash);
    }

    // @dev – challenge a superblock claim.
    // @param superblockHash – Id of the superblock to challenge.
    // @return - Error code and claim Id
    function challengeSuperblock(bytes32 superblockHash) public returns (uint, bytes32) {
        require(address(trustedSuperblocks) != address(0));

        SuperblockClaim storage claim = claims[superblockHash];

        if (!claimExists(claim)) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_BAD_CLAIM);
            return (ERR_SUPERBLOCK_BAD_CLAIM, superblockHash);
        }
        if (claim.decided) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_CLAIM_DECIDED);
            return (ERR_SUPERBLOCK_CLAIM_DECIDED, superblockHash);
        }
        if (deposits[msg.sender] < minChallengeDeposit) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_MIN_DEPOSIT);
            return (ERR_SUPERBLOCK_MIN_DEPOSIT, superblockHash);
        }

        uint err;
        (err, ) = trustedSuperblocks.challenge(superblockHash, msg.sender);
        if (err != 0) {
            emit ErrorClaim(superblockHash, err);
            return (err, 0);
        }

        (err, ) = this.bondDeposit(superblockHash, msg.sender, battleReward);
        assert(err == ERR_SUPERBLOCK_OK);

        claim.challengeTimeout = block.timestamp + superblockTimeout;
        claim.challengers.push(msg.sender);
        emit SuperblockClaimChallenged(superblockHash, msg.sender);

        if (!claim.verificationOngoing) {
            runNextBattleSession(superblockHash);
        }

        return (ERR_SUPERBLOCK_OK, superblockHash);
    }

    // @dev – runs a battle session to verify a superblock for the next challenger
    // @param superblockHash – claim id.
    function runNextBattleSession(bytes32 superblockHash) internal returns (bool) {
        SuperblockClaim storage claim = claims[superblockHash];

        if (!claimExists(claim)) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_BAD_CLAIM);
            return false;
        }

        // superblocks marked as invalid do not have to run remaining challengers
        if (claim.decided || claim.invalid) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_CLAIM_DECIDED);
            return false;
        }

        if (claim.verificationOngoing) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_VERIFICATION_PENDING);
            return false;
        }

        if (claim.currentChallenger < claim.challengers.length) {

            bytes32 sessionId = trustedDogeBattleManager.beginBattleSession(superblockHash, claim.submitter,
                claim.challengers[claim.currentChallenger]);

            claim.sessions[claim.challengers[claim.currentChallenger]] = sessionId;
            emit VerificationGameStarted(superblockHash, claim.submitter,
                claim.challengers[claim.currentChallenger], sessionId);

            claim.verificationOngoing = true;
            claim.currentChallenger += 1;
        }

        return true;
    }

    // @dev – check whether a claim has successfully withstood all challenges.
    // If successful without challenges, it will mark the superblock as confirmed.
    // If successful with at least one challenge, it will mark the superblock as semi-approved.
    // If verification failed, it will mark the superblock as invalid.
    //
    // @param superblockHash – claim ID.
    function checkClaimFinished(bytes32 superblockHash) public returns (bool) {
        SuperblockClaim storage claim = claims[superblockHash];

        if (!claimExists(claim)) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_BAD_CLAIM);
            return false;
        }

        // check that there is no ongoing verification game.
        if (claim.verificationOngoing) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_VERIFICATION_PENDING);
            return false;
        }

        // an invalid superblock can be rejected immediately
        if (claim.invalid) {
            // The superblock is invalid, submitter abandoned
            // or superblock data is inconsistent
            claim.decided = true;
            trustedSuperblocks.invalidate(claim.superblockHash, msg.sender);
            emit SuperblockClaimFailed(superblockHash, claim.submitter);
            doPayChallengers(superblockHash, claim);
            return false;
        }

        // check that the claim has exceeded the claim's specific challenge timeout.
        if (block.timestamp <= claim.challengeTimeout) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_NO_TIMEOUT);
            return false;
        }

        // check that all verification games have been played.
        if (claim.currentChallenger < claim.challengers.length) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_VERIFICATION_PENDING);
            return false;
        }

        claim.decided = true;

        bool confirmImmediately = false;
        // No challengers and parent approved; confirm immediately
        if (claim.challengers.length == 0) {
            bytes32 parentId = trustedSuperblocks.getSuperblockParentId(claim.superblockHash);
            DogeSuperblocks.Status status = trustedSuperblocks.getSuperblockStatus(parentId);
            if (status == DogeSuperblocks.Status.Approved) {
                confirmImmediately = true;
            }
        }

        if (confirmImmediately) {
            trustedSuperblocks.confirm(claim.superblockHash, msg.sender);
            unbondDeposit(superblockHash, claim.submitter);
            emit SuperblockClaimSuccessful(superblockHash, claim.submitter);
        } else {
            trustedSuperblocks.semiApprove(claim.superblockHash, msg.sender);
            emit SuperblockClaimPending(superblockHash, claim.submitter);
        }
        return true;
    }

    // @dev – confirm semi approved superblock.
    //
    // A semi approved superblock can be confirmed if it has several descendant
    // superblocks that are also semi-approved.
    // If none of the descendants were challenged they will also be confirmed.
    //
    // @param superblockHash – the claim ID.
    // @param descendantId - claim ID descendants
    function confirmClaim(bytes32 superblockHash, bytes32 descendantId) public returns (bool) {
        uint numSuperblocks = 0;
        bool confirmDescendants = true;
        bytes32 id = descendantId;
        SuperblockClaim storage claim = claims[id];
        while (id != superblockHash) {
            if (!claimExists(claim)) {
                emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_BAD_CLAIM);
                return false;
            }
            if (trustedSuperblocks.getSuperblockStatus(id) != DogeSuperblocks.Status.SemiApproved) {
                emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_BAD_STATUS);
                return false;
            }
            if (confirmDescendants && claim.challengers.length > 0) {
                confirmDescendants = false;
            }
            id = trustedSuperblocks.getSuperblockParentId(id);
            claim = claims[id];
            numSuperblocks += 1;
        }

        if (numSuperblocks < superblockConfirmations) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_MISSING_CONFIRMATIONS);
            return false;
        }
        if (trustedSuperblocks.getSuperblockStatus(id) != DogeSuperblocks.Status.SemiApproved) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_BAD_STATUS);
            return false;
        }

        bytes32 parentId = trustedSuperblocks.getSuperblockParentId(superblockHash);
        if (trustedSuperblocks.getSuperblockStatus(parentId) != DogeSuperblocks.Status.Approved) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_BAD_STATUS);
            return false;
        }

        (uint err, ) = trustedSuperblocks.confirm(superblockHash, msg.sender);
        if (err != ERR_SUPERBLOCK_OK) {
            emit ErrorClaim(superblockHash, err);
            return false;
        }
        emit SuperblockClaimSuccessful(superblockHash, claim.submitter);
        doPaySubmitter(superblockHash, claim);
        unbondDeposit(superblockHash, claim.submitter);

        if (confirmDescendants) {
            bytes32[] memory descendants = new bytes32[](numSuperblocks);
            id = descendantId;
            uint idx = 0;
            while (id != superblockHash) {
                descendants[idx] = id;
                id = trustedSuperblocks.getSuperblockParentId(id);
                idx += 1;
            }
            while (idx > 0) {
                idx -= 1;
                id = descendants[idx];
                claim = claims[id];
                (err, ) = trustedSuperblocks.confirm(id, msg.sender);
                require(err == ERR_SUPERBLOCK_OK);
                emit SuperblockClaimSuccessful(id, claim.submitter);
                doPaySubmitter(id, claim);
                unbondDeposit(id, claim.submitter);
            }
        }

        return true;
    }

    // @dev – Reject a semi approved superblock.
    //
    // Superblocks that are not in the main chain can be marked as
    // invalid.
    //
    // @param superblockHash – the claim ID.
    function rejectClaim(bytes32 superblockHash) public returns (bool) {
        SuperblockClaim storage claim = claims[superblockHash];
        if (!claimExists(claim)) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_BAD_CLAIM);
            return false;
        }

        uint height = trustedSuperblocks.getSuperblockHeight(superblockHash);
        bytes32 id = trustedSuperblocks.getBestSuperblock();
        if (trustedSuperblocks.getSuperblockHeight(id) < height + superblockConfirmations) {
            emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_MISSING_CONFIRMATIONS);
            return false;
        }

        id = trustedSuperblocks.getSuperblockAt(height);

        if (id != superblockHash) {
            DogeSuperblocks.Status status = trustedSuperblocks.getSuperblockStatus(superblockHash);

            if (status != DogeSuperblocks.Status.SemiApproved) {
                emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_BAD_STATUS);
                return false;
            }

            if (!claim.decided) {
                emit ErrorClaim(superblockHash, ERR_SUPERBLOCK_CLAIM_DECIDED);
                return false;
            }

            trustedSuperblocks.invalidate(superblockHash, msg.sender);
            emit SuperblockClaimFailed(superblockHash, claim.submitter);
            doPayChallengers(superblockHash, claim);
            return true;
        }

        return false;
    }

    // @dev – called when a battle session has ended.
    //
    // @param sessionId – session Id.
    // @param superblockHash - claim Id
    // @param winner – winner of verification game.
    // @param loser – loser of verification game.
    function sessionDecided(bytes32 sessionId, bytes32 superblockHash, address winner, address loser)
    public onlyBattleManager {
        SuperblockClaim storage claim = claims[superblockHash];

        require(claimExists(claim));

        claim.verificationOngoing = false;

        if (claim.submitter == loser) {
            // the claim is over.
            // Trigger end of verification game
            claim.invalid = true;
        } else if (claim.submitter == winner) {
            // the claim continues.
            // It should not fail when called from sessionDecided
            runNextBattleSession(superblockHash);
        } else {
            revert();
        }

        emit SuperblockBattleDecided(sessionId, winner, loser);
    }

    // @dev - Pay challengers than ran their battles with submitter deposits
    // Challengers that did not run will be returned their deposits
    function doPayChallengers(bytes32 superblockHash, SuperblockClaim storage claim) internal {
        uint rewards = claim.bondedDeposits[claim.submitter];
        claim.bondedDeposits[claim.submitter] = 0;
        uint totalDeposits = 0;
        uint idx = 0;
        for (idx = 0; idx < claim.currentChallenger; ++idx) {
            totalDeposits = totalDeposits.add(claim.bondedDeposits[claim.challengers[idx]]);
        }
        address challenger;
        uint reward;
        for (idx = 0; idx < claim.currentChallenger; ++idx) {
            challenger = claim.challengers[idx];
            reward = rewards.mul(claim.bondedDeposits[challenger]).div(totalDeposits);
            claim.bondedDeposits[challenger] = claim.bondedDeposits[challenger].add(reward);
        }
        uint bondedDeposit;
        for (idx = 0; idx < claim.challengers.length; ++idx) {
            challenger = claim.challengers[idx];
            bondedDeposit = claim.bondedDeposits[challenger];
            deposits[challenger] = deposits[challenger].add(bondedDeposit);
            claim.bondedDeposits[challenger] = 0;
            emit DepositUnbonded(superblockHash, challenger, bondedDeposit);
        }
    }

    // @dev - Pay submitter with challenger deposits
    function doPaySubmitter(bytes32 superblockHash, SuperblockClaim storage claim) internal {
        address challenger;
        uint bondedDeposit;
        for (uint idx = 0; idx < claim.challengers.length; ++idx) {
            challenger = claim.challengers[idx];
            bondedDeposit = claim.bondedDeposits[challenger];
            claim.bondedDeposits[challenger] = 0;
            claim.bondedDeposits[claim.submitter] = claim.bondedDeposits[claim.submitter].add(bondedDeposit);
        }
        unbondDeposit(superblockHash, claim.submitter);
    }

    // @dev - Check if a superblock can be semi approved by calling checkClaimFinished
    function getInBattleAndSemiApprovable(bytes32 superblockHash) public view returns (bool) {
        SuperblockClaim storage claim = claims[superblockHash];
        return (trustedSuperblocks.getSuperblockStatus(superblockHash) == DogeSuperblocks.Status.InBattle &&
            !claim.invalid && !claim.verificationOngoing && block.timestamp > claim.challengeTimeout
            && claim.currentChallenger >= claim.challengers.length);
    }

    // @dev – Check if a claim exists
    function claimExists(SuperblockClaim memory claim) private pure returns (bool) {
        return (claim.submitter != address(0x0));
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
        return claim.challengers.length - (claim.currentChallenger);
    }

    // @dev – Return session by challenger
    function getSession(bytes32 superblockHash, address challenger) public view returns(bytes32) {
        return claims[superblockHash].sessions[challenger];
    }

    function getClaimChallengers(bytes32 superblockHash) public view returns (address[] memory) {
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
        return trustedSuperblocks.getSuperblock(superblockHash);
    }
}

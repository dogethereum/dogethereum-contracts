// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import {DogeDepositsManager} from "./DogeDepositsManager.sol";
import {DogeSuperblocks} from "./DogeSuperblocks.sol";
import {DogeBattleManager} from "./DogeBattleManager.sol";
import {DogeMessageLibrary} from "./DogeParser/DogeMessageLibrary.sol";
import {DogeErrorCodes} from "./DogeErrorCodes.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// @dev - Manager of superblock claims
//
// Manages superblocks proposal and challenges
contract SuperblockClaims is DogeDepositsManager, DogeErrorCodes {

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

    /**
     * Confirmations required to confirm semi approved superblocks
     */
    uint public superblockConfirmations;

    /**
     * Monetary reward for opponent in case battle is lost
     */
    uint public battleReward;

    /**
     * Delay required to submit superblocks (in seconds)
     */
    uint public superblockDelay;
    /**
     * Timeout for action (in seconds)
     */
    uint public superblockTimeout;

    event DepositBonded(bytes32 superblockHash, address account, uint amount);
    event DepositUnbonded(bytes32 superblockHash, address account, uint amount);
    event SuperblockClaimCreated(bytes32 superblockHash, address submitter);
    event SuperblockClaimChallenged(bytes32 superblockHash, address challenger);
    event SuperblockBattleDecided(bytes32 sessionId, address winner, address loser);
    event SuperblockClaimSuccessful(bytes32 superblockHash, address submitter);
    event SuperblockClaimPending(bytes32 superblockHash, address submitter);
    event SuperblockClaimFailed(bytes32 superblockHash, address submitter);
    event VerificationGameStarted(bytes32 superblockHash, address submitter, address challenger, bytes32 sessionId);

    modifier onlyBattleManager() {
        require(msg.sender == address(trustedDogeBattleManager));
        _;
    }

    modifier onlyMeOrBattleManager() {
        require(msg.sender == address(trustedDogeBattleManager) || msg.sender == address(this));
        _;
    }

    /**
     * @dev – Sets up the contract managing superblock challenges
     *        All of these values are constant.
     * @param superblocks Contract that stores superblocks
     * @param battleManager Contract that manages battles
     * @param initSuperblockDelay Delay to accept a superblock submission (in seconds).
     * @param initSuperblockTimeout Time to wait for challenges (in seconds)
     * @param initSuperblockConfirmations Confirmations required to confirm semi approved superblocks
     */
    function initialize(
        DogeSuperblocks superblocks,
        DogeBattleManager battleManager,
        uint initSuperblockDelay,
        uint initSuperblockTimeout,
        uint initSuperblockConfirmations,
        uint initBattleReward
    ) external {
        require(address(trustedSuperblocks) == address(0), "SuperblockClaims already initialized.");
        require(address(superblocks) != address(0), "Superblocks contract must be valid.");
        require(address(battleManager) != address(0), "Battle manager contract must be valid.");

        trustedSuperblocks = superblocks;
        trustedDogeBattleManager = battleManager;
        superblockDelay = initSuperblockDelay;
        superblockTimeout = initSuperblockTimeout;
        superblockConfirmations = initSuperblockConfirmations;
        battleReward = initBattleReward;
    }

    // TODO: separate out this function into two: one internal and one external for the DogeBattleManager contract.
    /**
     * @dev Locks up part of a user's deposit into a claim.
     * @param superblockHash Claim id.
     * @param account User's address.
     * @param amount Amount of deposit to lock up.
     * @return user's deposit bonded for the claim.
     */
    function bondDeposit(bytes32 superblockHash, address account, uint amount) onlyMeOrBattleManager external returns (uint) {
        SuperblockClaim storage claim = claims[superblockHash];

        // Error: The claim for this superblock does not exist.
        require(claimExists(claim), "ERR_BOND_DEPOSIT_CLAIM_DOES_NOT_EXIST");

        // Error: Ether must be deposited to execute this action.
        require(deposits[account] >= amount, "ERR_BOND_DEPOSIT_NEEDS_DEPOSIT");

        deposits[account] = deposits[account].sub(amount);
        claim.bondedDeposits[account] = claim.bondedDeposits[account].add(amount);
        emit DepositBonded(superblockHash, account, amount);

        return claim.bondedDeposits[account];
    }

    // @dev – accessor for a claim's bonded deposits.
    // @param superblockHash – claim id.
    // @param account – user's address.
    // @return – user's deposit bonded for the claim.
    function getBondedDeposit(bytes32 superblockHash, address account) public view returns (uint) {
        SuperblockClaim storage claim = claims[superblockHash];
        // Error: The claim for this superblock does not exist.
        require(claimExists(claim), "ERR_BOND_DEPOSIT_CLAIM_DOES_NOT_EXIST");
        return claim.bondedDeposits[account];
    }

    function getDeposit(address account) override public view returns (uint) {
        return deposits[account];
    }

    // @dev – unlocks a user's bonded deposits from a claim.
    // @param superblockHash – claim id.
    // @param account – user's address.
    // @return – user's deposit which was unbonded from the claim.
    function unbondDeposit(bytes32 superblockHash, address account) internal returns (uint) {
        SuperblockClaim storage claim = claims[superblockHash];
        // Error: The claim for this superblock does not exist.
        require(claimExists(claim), "ERR_UNBOND_DEPOSIT_CLAIM_DOES_NOT_EXIST");
        // Error: The claim must be decided.
        require(claim.decided, "ERR_UNBOND_DEPOSIT_CLAIM_NOT_DECIDED");

        uint bondedDeposit = claim.bondedDeposits[account];

        delete claim.bondedDeposits[account];
        deposits[account] = deposits[account].add(bondedDeposit);

        emit DepositUnbonded(superblockHash, account, bondedDeposit);

        return bondedDeposit;
    }

    // @dev – Propose a new superblock.
    //
    // @param blocksMerkleRoot Root of the merkle tree of blocks contained in a superblock
    // @param accumulatedWork Accumulated proof of work of the last block in the superblock
    // @param timestamp Timestamp of the last block in the superblock
    // @param prevTimestamp Timestamp of the block previous to the last
    // @param lastHash Hash of the last block in the superblock
    // @param lastBits Difficulty bits of the last block in the superblock
    // @param parentHash Id of the parent superblock
    // @return Error code and superblockHash
    function proposeSuperblock(
        bytes32 blocksMerkleRoot,
        uint accumulatedWork,
        uint timestamp,
        uint prevTimestamp,
        bytes32 lastHash,
        uint32 lastBits,
        bytes32 parentHash
    ) public returns (bytes32) {
        // TODO: this address validity check looks out of place here
        require(address(trustedSuperblocks) != address(0));

        // Error: The submitter must deposit some ether as collateral to propose a superblock.
        require(
            deposits[msg.sender] >= minProposalDeposit,
            "ERR_PROPOSE_CLAIM_NEEDS_DEPOSIT"
        );

        // Error: New superblock should be based on confirmed dogecoin blocks.
        require(
            timestamp + superblockDelay <= block.timestamp,
            "ERR_PROPOSE_CLAIM_TIMESTAMP_TOO_RECENT"
        );

        bytes32 superblockHash = trustedSuperblocks.propose(blocksMerkleRoot, accumulatedWork,
            timestamp, prevTimestamp, lastHash, lastBits, parentHash, msg.sender);

        SuperblockClaim storage claim = claims[superblockHash];
        // Error: Superblock claim already exists.
        require(!claimExists(claim), "ERR_PROPOSED_CLAIM_ALREADY_EXISTS");

        claim.superblockHash = superblockHash;
        claim.submitter = msg.sender;
        claim.currentChallenger = 0;
        claim.decided = false;
        claim.invalid = false;
        claim.verificationOngoing = false;
        claim.createdAt = block.timestamp;
        claim.challengeTimeout = block.timestamp + superblockTimeout;

        this.bondDeposit(superblockHash, msg.sender, battleReward);

        emit SuperblockClaimCreated(superblockHash, msg.sender);

        return superblockHash;
    }

    // @dev – challenge a superblock claim.
    // @param superblockHash – Id of the superblock to challenge.
    // @return - Error code and claim Id
    function challengeSuperblock(bytes32 superblockHash) public returns (bytes32) {
        // TODO: this address validity check looks out of place here
        require(address(trustedSuperblocks) != address(0));

        SuperblockClaim storage claim = claims[superblockHash];

        // Error: The claim does not exist.
        require(claimExists(claim), "ERR_CHALLENGE_CLAIM_DOES_NOT_EXIST");
        // Error: The claim must be new.
        require(!claim.decided, "ERR_CHALLENGE_CLAIM_ALREADY_DECIDED");
        // Error: The challenger must deposit some ether as collateral to challenge a superblock.
        require(
            deposits[msg.sender] >= minChallengeDeposit,
            "ERR_CHALLENGE_CLAIM_NEEDS_DEPOSIT"
        );

        trustedSuperblocks.challenge(superblockHash, msg.sender);

        this.bondDeposit(superblockHash, msg.sender, battleReward);

        claim.challengeTimeout = block.timestamp + superblockTimeout;
        claim.challengers.push(msg.sender);
        emit SuperblockClaimChallenged(superblockHash, msg.sender);

        if (!claim.verificationOngoing) {
            runNextBattleSession(superblockHash);
        }

        return superblockHash;
    }

    // @dev – runs a battle session to verify a superblock for the next challenger
    // @param superblockHash – claim id.
    function runNextBattleSession(bytes32 superblockHash) internal returns (bool) {
        SuperblockClaim storage claim = claims[superblockHash];

        // Error: The claim does not exist.
        require(claimExists(claim), "ERR_NEXT_BATTLE_CLAIM_DOES_NOT_EXIST");

        // Error: The claim must not be decided nor invalid.
        // Superblock claims marked as invalid mustn't run remaining challenges.
        // TODO: invalid claims should be decided.
        // Restrict representable states to avoid allowing a claim to be undecided but invalid.
        require(!claim.decided && !claim.invalid, "ERR_NEXT_BATTLE_CLAIM_DECIDED");

        // Error: There's an ongoing verification battle for this claim.
        require(!claim.verificationOngoing, "ERR_NEXT_BATTLE_VERIFICATION_BATTLE_PENDING");

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

        // Error: The claim does not exist.
        require(claimExists(claim), "ERR_CHECK_CLAIM_DOES_NOT_EXIST");

        // Error: There's an ongoing verification battle for this claim.
        require(!claim.verificationOngoing, "ERR_CHECK_VERIFICATION_BATTLE_PENDING");

        // TODO: this invalid -> decided transition looks like it shouldn't even exist.
        // There should be no way to salvage an invalidated superblock.
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
        // Error: The claim can only be decided once a period of time has passed since the last challenge.
        require(
            block.timestamp > claim.challengeTimeout,
            "ERR_CHECK_CLAIM_NO_TIMEOUT"
        );

        // check that all verification games have been played.
        // Error: Claim cannot be decided until all challengers have had their turn at the verification game.
        require(
            claim.currentChallenger >= claim.challengers.length,
            "ERR_CHECK_VERIFICATION_GAMES_PENDING"
        );

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

    // @dev – confirms a range of semi approved superblocks.
    //
    // The range of superblocks is given by a semi approved superblock and one of its descendants.
    // This will attempt to confirm all superblocks in between them.
    //
    // A semi approved superblock can be confirmed if its parent is approved.
    // If none of the descendants were challenged they will also be confirmed.
    //
    // @param superblockHash – the claim ID of the superblock to be confirmed.
    // @param descendantId - claim ID of the last descendant to be confirmed.
    function confirmClaim(bytes32 superblockHash, bytes32 descendantId) public returns (bool) {
        uint numSuperblocks = 0;
        bool confirmDescendants = true;
        // Error: the given superblock claim is not semiapproved.
        require(
            trustedSuperblocks.getSuperblockStatus(superblockHash) == DogeSuperblocks.Status.SemiApproved,
            "ERR_CONFIRM_CLAIM_IS_NOT_SEMIAPPROVED"
        );

        bytes32 id = descendantId;
        SuperblockClaim storage claim = claims[id];
        // TODO: we probably want to refactor this loop into its own function.
        while (id != superblockHash) {
            // Error: One of the claims does not exist.
            require(claimExists(claim), "ERR_CONFIRM_CLAIM_DOES_NOT_EXIST");
            // Error: One of the superblocks is not semiapproved.
            require(
                trustedSuperblocks.getSuperblockStatus(id) == DogeSuperblocks.Status.SemiApproved,
                "ERR_CONFIRM_CLAIM_IS_NOT_SEMIAPPROVED"
            );
            confirmDescendants = confirmDescendants && claim.challengers.length == 0;
            id = trustedSuperblocks.getSuperblockParentId(id);
            claim = claims[id];
            numSuperblocks += 1;
        }

        // Error: Not enough confirmations for this superblock.
        require(numSuperblocks >= superblockConfirmations, "ERR_CONFIRM_CLAIM_MISSING_CONFIRMATIONS");

        bytes32 parentId = trustedSuperblocks.getSuperblockParentId(superblockHash);
        // Error: The parent superblock must be approved.
        require(
            trustedSuperblocks.getSuperblockStatus(parentId) == DogeSuperblocks.Status.Approved,
            "ERR_CONFIRM_CLAIM_PARENT_IS_NOT_APPROVED"
        );

        trustedSuperblocks.confirm(superblockHash, msg.sender);
        emit SuperblockClaimSuccessful(superblockHash, claim.submitter);
        doPaySubmitter(superblockHash, claim);
        unbondDeposit(superblockHash, claim.submitter);

        // TODO: it looks like this could use a refactor too.
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
                trustedSuperblocks.confirm(id, msg.sender);
                emit SuperblockClaimSuccessful(id, claim.submitter);
                doPaySubmitter(id, claim);
                unbondDeposit(id, claim.submitter);
            }
        }

        return true;
    }

    /**
     * @dev – Reject a semi approved superblock.
     *
     * Superblocks that are not in the main chain can be marked as
     * invalid.
     *
     * @param superblockHash – the claim ID.
     */
    function rejectClaim(bytes32 superblockHash) public returns (bool) {
        // TODO: the logic for determining if this block is in the canonical superblockchain or not
        // should be in the DogeSuperblocks contract.
        SuperblockClaim storage claim = claims[superblockHash];
        // Error: Claim does not exist.
        require(claimExists(claim), "ERR_REJECT_CLAIM_DOES_NOT_EXIST");

        uint height = trustedSuperblocks.getSuperblockHeight(superblockHash);
        bytes32 id = trustedSuperblocks.getBestSuperblock();
        // Error: Superblock is at a greater height than the superblock with greatest height approved.
        require(
            trustedSuperblocks.getSuperblockHeight(id) >= height + superblockConfirmations,
            "ERR_REJECT_CLAIM_POTENTIALLY_VALID"
        );

        id = trustedSuperblocks.getSuperblockAt(height);

        if (id != superblockHash) {
            DogeSuperblocks.Status status = trustedSuperblocks.getSuperblockStatus(superblockHash);

            // Error: The superblock must be semiapproved.
            require(status == DogeSuperblocks.Status.SemiApproved, "ERR_REJECT_CLAIM_NOT_SEMIAPPROVED");

            // Error: The superblock claim must be decided.
            require(claim.decided, "ERR_REJECT_CLAIM_NOT_DECIDED");

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

        // Error: Claim does not exist.
        require(claimExists(claim), "ERR_SESSION_DECIDED_CLAIM_DOES_NOT_EXIST");
        // Error: There is no ongoing verification battle for this claim.
        require(claim.verificationOngoing, "ERR_SESSION_DECIDED_NO_VERIFICATION_BATTLE");

        claim.verificationOngoing = false;

        if (claim.submitter == loser) {
            // the claim is over.
            // Trigger end of verification game
            // TODO: the claim should be considered "decided" at this point
            claim.invalid = true;
        } else if (claim.submitter == winner) {
            // the claim continues.
            // It should not fail when called from sessionDecided
            runNextBattleSession(superblockHash);
        } else {
            revert("Invalid session decision");
        }

        emit SuperblockBattleDecided(sessionId, winner, loser);
    }

    /**
     * @dev - Pay challengers than ran their battles with submitter deposits
     * Challengers that did not run will be returned their deposits
     */
    function doPayChallengers(bytes32 superblockHash, SuperblockClaim storage claim) internal {
        //TODO: This function has unbounded loops. This payment mechanism should be changed into a pull rather than push.
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
    function claimExists(SuperblockClaim storage claim) private view returns (bool) {
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
}

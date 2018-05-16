pragma solidity ^0.4.19;

import {DepositsManager} from './DepositsManager.sol';
import {Superblocks} from './Superblocks.sol';
import {BattleManager} from './BattleManager.sol';
import {DogeTx} from './DogeParser/DogeTx.sol';
import {SuperblockErrorCodes} from "./SuperblockErrorCodes.sol";


// @dev - Manager of superblock claims
//
// Manages superblocks proposal and challenges
contract ClaimManager is DepositsManager, BattleManager, SuperblockErrorCodes {
    uint private numClaims = 1;
    uint public minDeposit = 1;

    uint public defaultChallengeTimeout = 5;
    uint public superblocksDelta = 1 hours;

    event DepositBonded(bytes32 claimId, address account, uint amount);
    event DepositUnbonded(bytes32 claimId, address account, uint amount);
    event SuperblockClaimCreated(bytes32 claimId, address claimant, bytes32 superblockId);
    event SuperblockClaimChallenged(bytes32 claimId, address challenger);
    event SessionDecided(bytes32 sessionId, address winner, address loser);
    event SuperblockClaimSuccessful(bytes32 claimId, address claimant, bytes32 superblockId);
    event SuperblockClaimFailed(bytes32 claimId, address claimant, bytes32 superblockId);
    event VerificationGameStarted(bytes32 claimId, address claimant, address challenger, bytes32 sessionId);

    event ErrorClaim(bytes32 claimId, uint err);

    enum ChallengeState {
        Unchallenged,       // Unchallenged claim
        Challenged,         // Claims was challenged
        QueryHashes,        // Challenger expecting block hashes
        RespondHashes,      // Blcok hashes were received and verified
        QueryHeaders,       // Challenger is requesting block headers
        RespondHeaders,     // All block headers were received
        SuperblockVerified  // Superblock was verified
    }

    struct BlockInfo {
        uint difficulty;
        uint status;        // 0 - none, 1 - required, 2 - replied
    }

    struct SuperblockClaim {
        address claimant;                           // Superblock submitter
        bytes32 superblockId;                       // Superblock Id
        uint createdAt;                             // Block when claim was created
        uint timestamp;                             // Superblock timestamp

        address[] challengers;                      // List of challengers
        mapping (address => uint) idxChallengers;   // Index of challengers (position + 1 in challengers array)
        mapping (address => uint) bondedDeposits;   // Deposit associated to challengers

        uint currentChallenger;                     // Index of challenger in current session
        mapping (address => bytes32) sessions;      // Challenge sessions

        uint challengeTimeoutBlockNumber;           // Next timeout
        bool verificationOngoing;                   // Challenge session has started

        bool decided;                               // If the claim was decided
        bool invalid;                               // If superblock is invalid

        ChallengeState challengeState;              // Claim state
        bytes32[] blockHashes;                      // Block hashes
        uint countBlockHeaderQueries;               // Number of block header queries
        uint countBlockHeaderResponses;             // Number of block header responses
        mapping(bytes32 => BlockInfo) blocksInfo;
        uint accumulatedWork;
        uint lastBlockTimestamp;
    }

    // Active Superblock claims
    mapping(bytes32 => SuperblockClaim) private claims;

    Superblocks superblocks;

    modifier onlyBy(address _account) {
        require(msg.sender == _account);
        _;
    }

    // @dev – Configures the contract storing the superblocks
    // @param _superblocks Contract that manages superblocks
    function ClaimManager(Superblocks _superblocks) public {
        superblocks = _superblocks;
    }

    // @dev – locks up part of the a user's deposit into a claim.
    // @param claimId – the claim id.
    // @param account – the user's address.
    // @param amount – the amount of deposit to lock up.
    // @return – the user's deposit bonded for the claim.
    function bondDeposit(bytes32 claimId, address account, uint amount) private returns (uint) {
        SuperblockClaim storage claim = claims[claimId];

        require(claimExists(claim));
        require(deposits[account] >= amount);
        deposits[account] -= amount;

        claim.bondedDeposits[account] += amount;
        emit DepositBonded(claimId, account, amount);
        return claim.bondedDeposits[account];
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
    function unbondDeposit(bytes32 claimId, address account) public returns (uint) {
        SuperblockClaim storage claim = claims[claimId];
        require(claimExists(claim));
        require(claim.decided == true);

        uint bondedDeposit = claim.bondedDeposits[account];

        delete claim.bondedDeposits[account];
        deposits[account] += bondedDeposit;

        emit DepositUnbonded(claimId, account, bondedDeposit);

        return bondedDeposit;
    }

    // @dev – Propose a new superblock.
    //
    // @param _blocksMerkleRoot Root of the merkle tree of blocks contained in a superblock
    // @param _accumulatedWork Accumulated proof of work of the last block in the superblock
    // @param _timestamp Timestamp of the last block in the superblock
    // @param _lastHash Hash of the last block in the superblock
    // @param _parentId Id of the parent superblock
    // @return Error code and superblockId
    function proposeSuperblock(bytes32 _blocksMerkleRoot, uint _accumulatedWork, uint _timestamp, bytes32 _lastHash, bytes32 _parentHash) public returns (uint, bytes32) {
        if (deposits[msg.sender] < minDeposit) {
            emit ErrorClaim(0, ERR_SUPERBLOCK_MIN_DEPOSIT);
            return (ERR_SUPERBLOCK_MIN_DEPOSIT, 0);
        }

        uint err;
        bytes32 superblockId;
        (err, superblockId) = superblocks.propose(_blocksMerkleRoot, _accumulatedWork, _timestamp, _lastHash, _parentHash, msg.sender);
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

        claim.claimant = msg.sender;
        claim.currentChallenger = 0;
        claim.decided = false;
        claim.invalid = false;
        claim.verificationOngoing = false;
        claim.createdAt = block.number;
        claim.challengeTimeoutBlockNumber = block.number;
        claim.superblockId = superblockId;
        claim.challengeState = ChallengeState.Unchallenged;
        claim.timestamp = _timestamp;

        bondDeposit(claimId, msg.sender, minDeposit);

        emit SuperblockClaimCreated(claimId, msg.sender, superblockId);

        return (ERR_SUPERBLOCK_OK, superblockId);
    }

    // @dev – challenge a superblock claim.
    // @param superblockId – Id of the superblock to challenge.
    // @return Error code an claim Id
    function challengeSuperblock(bytes32 superblockId) public returns (uint, bytes32) {
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
        if (claim.idxChallengers[msg.sender] != 0) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_BAD_CHALLENGER);
            return (ERR_SUPERBLOCK_BAD_CHALLENGER, claimId);
        }

        uint err;
        (err, ) = superblocks.challenge(superblockId);
        if (err != 0) {
            emit ErrorClaim(claimId, err);
            return (err, 0);
        }

        bondDeposit(claimId, msg.sender, minDeposit);

        claim.challengeTimeoutBlockNumber += defaultChallengeTimeout;
        claim.challengers.push(msg.sender);
        claim.idxChallengers[msg.sender] = claim.challengers.length;
        claim.challengeState = ChallengeState.Challenged;
        emit SuperblockClaimChallenged(claimId, msg.sender);

        return (ERR_SUPERBLOCK_OK, claimId);
    }

    // @dev – runs the battle session to verify a superblock for the next challenger
    // @param claimId – the claim id.
    function runNextBattleSession(bytes32 claimId) public returns (bool) {
        SuperblockClaim storage claim = claims[claimId];

        if (!claimExists(claim)) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_BAD_CLAIM);
            return false;
        }

        if (claim.decided) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_CLAIM_DECIDED);
            return false;
        }

        if (claim.verificationOngoing) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_VERIFICATION_PENDING);
            return false;
        }

        if (claim.currentChallenger < claim.challengers.length) {

            bytes32 sessionId = beginBattleSession(claimId, claim.challengers[claim.currentChallenger], claim.claimant);

            claim.sessions[claim.challengers[claim.currentChallenger]] = sessionId;
            emit VerificationGameStarted(claimId, claim.claimant, claim.challengers[claim.currentChallenger], sessionId);

            claim.verificationOngoing = true;
            claim.currentChallenger += 1;
        }

        return true;
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

        //TODO Fix reward splitting
        // reward the winner, with the loser's bonded deposit.
        //uint depositToTransfer = claim.bondedDeposits[loser];
        //claim.bondedDeposits[winner] += depositToTransfer;
        //delete claim.bondedDeposits[loser];

        if (claim.claimant == loser) {
            // the claim is over.
            // note: no callback needed to the DogeRelay contract,
            // because it by default does not save blocks.

            //Trigger end of verification game
            claim.invalid = true;

            // It should not fail when called from sessionDecided
            // the data should be verified and a out of gas will cause
            // the whole transaction to revert
            runNextBattleSession(claimId);
        } else if (claim.claimant == winner) {
            // the claim continues.
            // It should not fail when called from sessionDecided
            runNextBattleSession(claimId);
        } else {
            revert();
        }

        emit SessionDecided(sessionId, winner, loser);
    }

    // @dev – check whether a claim has successfully withstood all challenges.
    // if successful, it will trigger a callback to the DogeRelay contract,
    // notifying it that the Scrypt blockhash was correctly calculated.
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

        // check that the claim has exceeded the default challenge timeout.
        if (block.number -  claim.createdAt <= defaultChallengeTimeout) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_NOT_TIMEOUT);
            return false;
        }

        //check that the claim has exceeded the claim's specific challenge timeout.
        if (block.number <= claim.challengeTimeoutBlockNumber) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_NOT_TIMEOUT);
            return false;
        }

        // check that all verification games have been played.
        if (claim.currentChallenger < claim.challengers.length) {
            emit ErrorClaim(claimId, ERR_SUPERBLOCK_VERIFICATION_PENDING);
            return false;
        }

        claim.decided = true;

        // If no challengers confirm immediately
        if (claim.invalid) {
            superblocks.invalidate(claim.superblockId);
            emit SuperblockClaimFailed(claimId, claim.claimant, claim.superblockId);
        } else {
            if (claim.challengers.length == 0) {
                superblocks.confirm(claim.superblockId);
            } else {
                superblocks.semiApprove(claim.superblockId);
            }
            unbondDeposit(claimId, claim.claimant);
            emit SuperblockClaimSuccessful(claimId, claim.claimant, claim.superblockId);
        }

        return true;
    }

    // @dev – Check if a claim exists
    function claimExists(SuperblockClaim claim) pure private returns(bool) {
        return claim.claimant != 0x0;
    }

    // @dev – Return session by challenger
    function getSession(bytes32 claimId, address challenger) public view returns(bytes32) {
        return claims[claimId].sessions[challenger];
    }

    // @dev – Make a query for superblock hashes
    function queryHashes(bytes32 claimId) internal {
        SuperblockClaim storage claim = claims[claimId];
        if (claim.challengeState == ChallengeState.Challenged) {
            claim.challengeState = ChallengeState.QueryHashes;
        }
    }

    // @dev – Verify an array of hashes matches superblock merkleroot
    function verifyHashes(bytes32 claimId, bytes data) internal {
        SuperblockClaim storage claim = claims[claimId];
        require(claim.blockHashes.length == 0);
        if (claim.challengeState == ChallengeState.QueryHashes) {
            claim.challengeState = ChallengeState.RespondHashes;
            require(data.length % 32 == 0);
            uint count = data.length / 32;
            for (uint i=0; i<count; ++i) {
                claim.blockHashes.push(DogeTx.readBytes32(data, 32*i));
            }
            bytes32 merkleRoot = DogeTx.makeMerkle(claim.blockHashes);
            require(merkleRoot == superblocks.getSuperblockMerkleRoot(claim.superblockId));
        }
    }

    // @dev – Make a query for superblock block headers
    function queryBlockHeader(bytes32 claimId, bytes32 blockHash) internal {
        SuperblockClaim storage claim = claims[claimId];
        if (claim.challengeState == ChallengeState.RespondHashes || claim.challengeState == ChallengeState.QueryHeaders) {
            require(claim.countBlockHeaderQueries < claim.blockHashes.length);
            require(claim.blocksInfo[blockHash].status == 0);
            claim.countBlockHeaderQueries += 1;
            claim.blocksInfo[blockHash].status = 1;
            claim.challengeState = ChallengeState.QueryHeaders;
        }
    }

    uint constant DOGECOIN_HEADER_VERSION_OFFSET = 0;
    uint constant DOGECOIN_HEADER_PARENT_OFFSET = 4;
    uint constant DOGECOIN_HEADER_MERKLEROOT_OFFSET = 36;
    uint constant DOGECOIN_HEADER_TIMESTAMP_OFFSET = 68;
    uint constant DOGECOIN_HEADER_DIFFICULTY_OFFSET = 72;
    uint constant DOGECOIN_HEADER_NONCE_OFFSET = 76;

    // @dev - Verify a block header data correspond to a block hash in the superblock
    function verifyBlockHeader(bytes32 claimId, bytes data) internal {
        SuperblockClaim storage claim = claims[claimId];
        bytes32 scryptHash = DogeTx.readBytes32(data, 0);
        if (claim.challengeState == ChallengeState.QueryHeaders) {
            bytes32 blockHash = bytes32(DogeTx.dblShaFlipMem(data, 32, 80));
            require(claim.blocksInfo[blockHash].status == 1);
            claim.blocksInfo[blockHash].status = 2;
            claim.countBlockHeaderResponses += 1;

            uint timestamp = DogeTx.getBytesLE(data, 32 + DOGECOIN_HEADER_TIMESTAMP_OFFSET, 32);

            // Block timestamp to be within the expected timestamp of the superblock
            require(timestamp / superblocksDelta <= claim.timestamp / superblocksDelta);
            require(timestamp / superblocksDelta >= claim.timestamp / superblocksDelta - 1);

            uint difficulty = DogeTx.getBytesLE(data, 32 + DOGECOIN_HEADER_DIFFICULTY_OFFSET, 32);

            claim.blocksInfo[blockHash].difficulty = difficulty;

            if (blockHash == claim.blockHashes[claim.blockHashes.length - 1]) {
                claim.lastBlockTimestamp = timestamp;
                // require(timestamp == claim.timestamp);
            }

            //FIXME: start scrypt hash verification
            // storeBlockHeader(data, uint(scryptHash));

            if (claim.countBlockHeaderResponses == claim.blockHashes.length) {
                claim.challengeState = ChallengeState.RespondHeaders;
            }
        }
    }

    // @dev - Verify all block header matches superblock accumulated work
    function verifySuperblock(bytes32 claimId) internal returns (bool) {
        SuperblockClaim storage claim = claims[claimId];
        if (claim.challengeState == ChallengeState.RespondHeaders) {
            claim.challengeState = ChallengeState.SuperblockVerified;
            bytes32 superblockId = claim.superblockId;
            bytes32 lastHash = superblocks.getSuperblockLastHash(superblockId);

            require(claim.lastBlockTimestamp != 0 && claim.lastBlockTimestamp == claim.timestamp);

            return true;
        }
        return false;
    }

}

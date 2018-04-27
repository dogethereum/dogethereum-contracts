pragma solidity ^0.4.19;

import {DepositsManager} from './DepositsManager.sol';
import {Superblocks} from './Superblocks.sol';
import {BattleManager} from './BattleManager.sol';


// @dev - Manager of superblock claims
//
// Manages superblocks proposal and challenges
contract ClaimManager is DepositsManager, BattleManager {
    uint private numClaims = 1;
    uint public minDeposit = 1;

    uint public defaultChallengeTimeout = 5;

    event DepositBonded(bytes32 claimId, address account, uint amount);
    event DepositUnbonded(bytes32 claimId, address account, uint amount);
    //event ClaimCreated(uint claimID, address claimant, bytes plaintext, bytes blockHash);
    event SuperblockClaimCreated(bytes32 claimId, address claimant, bytes32 superblockId);
    event SuperblockClaimChallenged(bytes32 claimId, address challenger);
    event SessionDecided(bytes32 sessionId, address winner, address loser);
    event SuperblockClaimSuccessful(bytes32 claimId, address claimant, bytes32 superblockId);
    event SuperblockClaimFailed(bytes32 claimId, address claimant, bytes32 superblockId);
    event VerificationGameStarted(bytes32 claimId, address claimant, address challenger, bytes32 sessionId);//Rename to SessionStarted?
    //event ClaimVerificationGamesEnded(uint claimID);

    enum ClaimState {
        Unchallenged,       // Unchallenged claim
        Challenged,         // Claims was challenged
        QueryHashes,        // Challenger expecting block hashes
        RespondHashes,      // Blcok hashes were received and verified
        QueryHeaders,       // Challenger is requesting block headers
        RespondHeaders      // All block headers were received
    }

    struct SuperblockClaim {
        address claimant;           // Superblock submitter
        bytes32 superblockId;       // Superblock Id
        uint createdAt;
        address[] challengers;      // List of challengers
        mapping(address => bytes32) sessions;       // Challenge sessions
        uint numChallengers;        // Total challngers
        uint currentChallenger;     // Index of challenger in current session
        bool verificationOngoing;   // Challenge session has started
        mapping (address => uint) bondedDeposits;   // Deposit associated to challengers
        bool decided;               // If the claim was decided
        uint challengeTimeoutBlockNumber;           // Next timeout
        ClaimState state;           // Claim state
        bytes32[] blockHashes;      // Block hashes
        uint countBlockHeaderQueries;               // Number of block header queries
        uint countBlockHeaderResponses;             // Number of block header respones
        mapping(bytes32 => uint) blockHeaderQueries;  // 0 - none, 1 - required, 2 - replied
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
    // @param claimID – the claim id.
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
    // @param claimID – the claim id.
    // @param account – the user's address.
    // @return – the user's deposit bonded for the claim.
    function getBondedDeposit(bytes32 claimId, address account) public view returns (uint) {
        SuperblockClaim storage claim = claims[claimId];
        require(claimExists(claim));
        return claim.bondedDeposits[account];
    }

    // @dev – unlocks a user's bonded deposits from a claim.
    // @param claimID – the claim id.
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
        address _submitter = msg.sender;

        if (deposits[_submitter] < minDeposit) {
            return (ERR_SUPERBLOCK_MIN_DEPOSIT, 0);
        }

        uint err;
        bytes32 superblockId;
        (err, superblockId) = superblocks.propose(_blocksMerkleRoot, _accumulatedWork, _timestamp, _lastHash, _parentHash);
        if (err != 0) {
            return (err, superblockId);
        }

        bytes32 claimId = superblockId;
        require(!claimExists(claims[claimId]));

        SuperblockClaim storage claim = claims[claimId];
        claim.claimant = _submitter;
        claim.numChallengers = 0;
        claim.currentChallenger = 0;
        claim.decided = false;
        claim.verificationOngoing = false;
        claim.createdAt = block.number;
        claim.superblockId = superblockId;
        claim.state = ClaimState.Unchallenged;

        bondDeposit(claimId, claim.claimant, minDeposit);
        emit SuperblockClaimCreated(claimId, claim.claimant, superblockId);

        return (ERR_SUPERBLOCK_OK, superblockId);
    }

    // @dev – challenge a superblock claim.
    // @param superblockId – Id of the superblock to challenge.
    // @return Error code an claim Id
    function challengeSuperblock(bytes32 superblockId) public returns (uint, bytes32) {
        bytes32 claimId = superblockId;
        SuperblockClaim storage claim = claims[claimId];

        require(claimExists(claim));
        require(!claim.decided);
        require(claim.sessions[msg.sender] == 0);

        require(deposits[msg.sender] >= minDeposit);
        bondDeposit(claimId, msg.sender, minDeposit);

        uint err;
        (err, ) = superblocks.challenge(superblockId);
        if (err != 0) {
            return (err, 0);
        }

        claim.challengeTimeoutBlockNumber += defaultChallengeTimeout;
        claim.challengers.push(msg.sender);
        claim.numChallengers += 1;
        claim.state = ClaimState.Challenged;
        emit SuperblockClaimChallenged(claimId, msg.sender);

        return (ERR_SUPERBLOCK_OK, claimId);
    }

    // @dev – runs the battle session to verify a superblock for the next challenger
    // @param claimID – the claim id.
    function runNextBattleSession(bytes32 claimId) public {
        SuperblockClaim storage claim = claims[claimId];

        require(claimExists(claim));
        require(!claim.decided);

        require(claim.verificationOngoing == false);

        if (claim.numChallengers > claim.currentChallenger) {

            bytes32 sessionId = beginBattleSession(claimId, claim.challengers[claim.currentChallenger], claim.claimant);

            claim.sessions[claim.challengers[claim.currentChallenger]] = sessionId;
            emit VerificationGameStarted(claimId, claim.claimant, claim.challengers[claim.currentChallenger], sessionId);

            claim.verificationOngoing = true;
            claim.currentChallenger += 1;
        } else {

        }
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
            claim.numChallengers = 0;
            runNextBattleSession(claimId);
        } else if (claim.claimant == winner) {
            // the claim continues.
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
    // @param claimID – the claim ID.
    function checkClaimFinished(bytes32 claimId) public {
        SuperblockClaim storage claim = claims[claimId];

        require(claimExists(claim));

        // check that there is no ongoing verification game.
        require(claim.verificationOngoing == false);

        //FIXME: Enforce timeouts
        // check that the claim has exceeded the default challenge timeout.
        //require(block.number -  claim.createdAt > defaultChallengeTimeout);

        //check that the claim has exceeded the claim's specific challenge timeout.
        //require(block.number > claim.challengeTimeoutBlockNumber);

        // check that all verification games have been played.
        require(claim.numChallengers <= claim.currentChallenger);

        claim.decided = true;

        if (claim.challengers.length == 0) {
            superblocks.confirm(claim.superblockId);
        } else {
            superblocks.semiApprove(claim.superblockId);
        }

        unbondDeposit(claimId, claim.claimant);

        emit SuperblockClaimSuccessful(claimId, claim.claimant, claim.superblockId);
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
        if (claim.state == ClaimState.Challenged) {
            claim.state = ClaimState.QueryHashes;
        } else {
        }
    }

    // @dev – Make a query for superblock block headers
    function queryBlockHeader(bytes32 claimId, bytes32 blockHash) internal {
        SuperblockClaim storage claim = claims[claimId];
        if (claim.state == ClaimState.RespondHashes || claim.state == ClaimState.QueryHeaders) {
            require(claim.countBlockHeaderQueries < claim.blockHashes.length);
            require(claim.blockHeaderQueries[blockHash] == 0);
            claim.countBlockHeaderQueries += 1;
            claim.blockHeaderQueries[blockHash] = 1;
            claim.state = ClaimState.QueryHeaders;
        } else {

        }
    }

    // @dev – Return a bytes32 at index in a byte array
    function readBytes32(bytes data, uint index) internal pure returns (bytes32) {
        bytes32 result;
        assembly {
            result := mload(add(add(data, 0x20), mul(32, index)))
        }
        return result;
    }

    // @dev – Verify an array of hashes matches superblock merkleroot
    function verifyHashes(bytes32 claimId, bytes data) internal {
        SuperblockClaim storage claim = claims[claimId];
        require(claim.blockHashes.length == 0);
        if (claim.state == ClaimState.QueryHashes) {
            claim.state = ClaimState.RespondHashes;
            require(data.length % 32 == 0);
            uint count = data.length / 32;
            for (uint i=0; i<count; ++i) {
                claim.blockHashes.push(readBytes32(data, i));
            }
            require(superblocks.verifyMerkleRoot(claim.superblockId, claim.blockHashes));
        }
    }

    // @dev – Calc sha256 of a sequence of bytes in a byte array
    function sha256mem(bytes memory _rawBytes, uint offset, uint len) internal view returns (bytes32 result) {
        assembly {
            // Call sha256 precompiled contract (located in address 0x02) to copy data.
            // Assign to ptr the next available memory position (stored in memory position 0x40).
            let ptr := mload(0x40)
            if iszero(staticcall(gas, 0x02, add(add(_rawBytes, 0x20), offset), len, ptr, 0x20)) {
                revert(0, 0)
            }
            result := mload(ptr)
        }
    }

    // @dev - Verify a block header data correspond to a block hash in the superblock
    function verifyBlockHeader(bytes32 claimId, bytes data) internal {
        SuperblockClaim storage claim = claims[claimId];
        bytes32 scryptHash = readBytes32(data, 0);
        if (claim.state == ClaimState.QueryHeaders) {
            bytes32 blockHash = sha256(sha256mem(data, 32, data.length - 32));
            require(claim.blockHeaderQueries[blockHash] == 1);
            claim.blockHeaderQueries[blockHash] = 2;
            claim.countBlockHeaderResponses += 1;

            //FIXME: start scrypt hash verification
            // storeBlockHeader(data, uint(scryptHash));

            if (claim.countBlockHeaderResponses == claim.blockHashes.length) {
                claim.state = ClaimState.RespondHeaders;
            }
        }
    }

    // @dev - Verify all block header matches superblock accumulated work
    function verifySuperblock(bytes32 claimId) internal returns (bool) {
        SuperblockClaim storage claim = claims[claimId];
        if (claim.state == ClaimState.RespondHeaders) {
            //FIXME: Verify timestamps & proof of work
            return true;
        }
        return false;
    }

    //FIXME: Consolidate with error constants in Superblocks in a single file
    // Error codes
    uint constant ERR_SUPERBLOCK_OK = 0;
    uint constant ERR_SUPERBLOCK_EXIST = 50010;
    uint constant ERR_SUPERBLOCK_BAD_STATUS = 50020;
    uint constant ERR_SUPERBLOCK_TIMEOUT = 50030;
    uint constant ERR_SUPERBLOCK_INVALID_MERKLE = 50040;
    uint constant ERR_SUPERBLOCK_BAD_PARENT = 50050;

    uint constant ERR_SUPERBLOCK_MIN_DEPOSIT = 50060;
}

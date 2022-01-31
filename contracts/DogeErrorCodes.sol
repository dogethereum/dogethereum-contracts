// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

// @dev - DogeSuperblocks error codes
contract DogeErrorCodes {
    // Error codes
    uint256 constant ERR_SUPERBLOCK_OK = 0;
    uint256 constant ERR_SUPERBLOCK_EXIST = 50010;
    uint256 constant ERR_SUPERBLOCK_BAD_STATUS = 50020;
    uint256 constant ERR_SUPERBLOCK_BAD_DOGE_STATUS = 50025;
    uint256 constant ERR_SUPERBLOCK_NO_TIMEOUT = 50030;
    uint256 constant ERR_SUPERBLOCK_BAD_TIMESTAMP = 50035;
    uint256 constant ERR_SUPERBLOCK_INVALID_MERKLE = 50040;
    uint256 constant ERR_SUPERBLOCK_BAD_PARENT = 50050;

    uint256 constant ERR_SUPERBLOCK_MIN_DEPOSIT = 50060;

    uint256 constant ERR_SUPERBLOCK_NOT_CLAIMMANAGER = 50070;

    uint256 constant ERR_SUPERBLOCK_BAD_CLAIM = 50080;
    uint256 constant ERR_SUPERBLOCK_VERIFICATION_PENDING = 50090;
    uint256 constant ERR_SUPERBLOCK_CLAIM_DECIDED = 50100;
    uint256 constant ERR_SUPERBLOCK_BAD_CHALLENGER = 50110;

    uint256 constant ERR_SUPERBLOCK_BAD_ACCUMULATED_WORK = 50120;
    uint256 constant ERR_SUPERBLOCK_BAD_BITS = 50130;
    uint256 constant ERR_SUPERBLOCK_MISSING_CONFIRMATIONS = 50140;
    uint256 constant ERR_SUPERBLOCK_BAD_LASTBLOCK = 50150;

    // error codes for verifyTx
    uint256 constant ERR_BAD_FEE = 20010;
    uint256 constant ERR_CONFIRMATIONS = 20020;
    uint256 constant ERR_CHAIN = 20030;
    uint256 constant ERR_SUPERBLOCK = 20040;
    uint256 constant ERR_MERKLE_ROOT = 20050;
    uint256 constant ERR_TX_64BYTE = 20060;

    // error codes for relayTx
    uint256 constant ERR_RELAY_VERIFY = 30010;

    // Minimum gas requirements
    uint256 public constant minReward = 400000;
    uint256 public constant superblockCost = 440000;
    uint256 public constant challengeCost = 34000;
    uint256 public constant minProposalDeposit = challengeCost + minReward;
    uint256 public constant minChallengeDeposit = superblockCost + minReward;
    uint256 public constant queryMerkleRootHashesCost = 88000;
    uint256 public constant queryBlockHeaderCost = 102000;
    uint256 public constant respondMerkleRootHashesCost = 378000; // TODO: measure this with 60 hashes
    uint256 public constant respondBlockHeaderCost = 40000;
    uint256 public constant requestScryptCost = 80000;
    uint256 public constant verifySuperblockCost = 220000;
}

pragma solidity 0.5.16;

// @dev - DogeSuperblocks error codes
contract DogeErrorCodes {
    // Error codes
    uint constant ERR_SUPERBLOCK_OK = 0;
    uint constant ERR_SUPERBLOCK_EXIST = 50010;
    uint constant ERR_SUPERBLOCK_BAD_STATUS = 50020;
    uint constant ERR_SUPERBLOCK_BAD_DOGE_STATUS = 50025;
    uint constant ERR_SUPERBLOCK_NO_TIMEOUT = 50030;
    uint constant ERR_SUPERBLOCK_BAD_TIMESTAMP = 50035;
    uint constant ERR_SUPERBLOCK_INVALID_MERKLE = 50040;
    uint constant ERR_SUPERBLOCK_BAD_PARENT = 50050;

    uint constant ERR_SUPERBLOCK_MIN_DEPOSIT = 50060;

    uint constant ERR_SUPERBLOCK_NOT_CLAIMMANAGER = 50070;

    uint constant ERR_SUPERBLOCK_BAD_CLAIM = 50080;
    uint constant ERR_SUPERBLOCK_VERIFICATION_PENDING = 50090;
    uint constant ERR_SUPERBLOCK_CLAIM_DECIDED = 50100;
    uint constant ERR_SUPERBLOCK_BAD_CHALLENGER = 50110;

    uint constant ERR_SUPERBLOCK_BAD_ACCUMULATED_WORK = 50120;
    uint constant ERR_SUPERBLOCK_BAD_BITS = 50130;
    uint constant ERR_SUPERBLOCK_MISSING_CONFIRMATIONS = 50140;
    uint constant ERR_SUPERBLOCK_BAD_LASTBLOCK = 50150;

    // error codes for verifyTx
    uint constant ERR_BAD_FEE = 20010;
    uint constant ERR_CONFIRMATIONS = 20020;
    uint constant ERR_CHAIN = 20030;
    uint constant ERR_SUPERBLOCK = 20040;
    uint constant ERR_MERKLE_ROOT = 20050;
    uint constant ERR_TX_64BYTE = 20060;

    // error codes for relayTx
    uint constant ERR_RELAY_VERIFY = 30010;

    // Minimum gas requirements
    uint constant public minReward = 400000;
    uint constant public superblockCost = 440000;
    uint constant public challengeCost = 34000;
    uint constant public minProposalDeposit = challengeCost + minReward;
    uint constant public minChallengeDeposit = superblockCost + minReward;
    uint constant public queryMerkleRootHashesCost = 88000;
    uint constant public queryBlockHeaderCost = 102000;
    uint constant public respondMerkleRootHashesCost = 378000; // TODO: measure this with 60 hashes
    uint constant public respondBlockHeaderCost = 40000;
    uint constant public requestScryptCost = 80000;
    uint constant public verifySuperblockCost = 220000;
}

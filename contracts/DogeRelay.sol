pragma solidity ^0.4.19;

import "./TransactionProcessor.sol";
import "./IScryptChecker.sol";
import "./IDogeRelay.sol";

contract DogeRelay is IDogeRelay {

    enum Network { MAINNET, TESTNET, REGTEST }

    // Number of block ancestors stored in BlockInformation._ancestor
    uint constant private NUM_ANCESTOR_DEPTHS = 8;

    // list for internal usage only that allows a 32 byte blockHash to be looked up
    // with a 32bit int
    // This is not designed to be used for anything else; it contains all block
    // hashes and nothing can be assumed about which blocks are on the main chain
    mapping (uint32 => uint) private internalBlock;

    // counter for next available slot in internalBlock.
    // 0 means no blocks stored yet and is used for the special cases of storing the first and second blocks in storeBlockHeader,
    // whose Dogecoin difficulty can't be computed since the first block's parent (i.e. the second block's grandparent)
    // isn't stored in DogeRelay.
    // Note: if setInitialParent is called with a block other than genesis,
    // this keeps track of *how many blocks have been stored in DogeRelay*,
    // not Dogecoin chain height.
    uint32 private ibIndex;

    // a Dogecoin block (header) is stored as:
    // - _blockHeader: version, timestamp, bits, nonce, block hash, previous block hash and Merkle root,
    // stored as a struct
    // - _info: 32 bytes consisting of block height (8bytes), internal block index (8bytes), score/amount of work (16bytes)
    // -   "_height" is 1 more than the typical Bitcoin term height/blocknumber [see setInitialParent()]
    // -   "_ibIndex" is the block's index to internalBlock (see btcChain)
    // -   "_score" is 1 more than the chainWork [see setInitialParent()]
    // - _ancestor: stores 8 32bit ancestor indices for more efficient backtracking (see btcChain)
    // - _feeInfo is used for incentive.se (see m_getFeeInfo)
    struct BlockInformation {
          BlockHeader _blockHeader;
          uint _info;
          uint _ancestor;
          // bytes _feeInfo;
    }

    // Dogecoin block header stored as a struct, mostly for readability purposes.
    // BlockHeader structs can be obtained by parsing a block header's first 80 bytes
    // with parseHeaderBytes.
    struct BlockHeader {
        uint32 version;
        uint32 time;
        uint32 bits;
        uint32 nonce;
        uint blockHash;
        uint prevBlock;
        uint merkleRoot;
    }

    //BlockInformation[] myblocks = new BlockInformation[](2**256);
    // block hash => BlockInformation
    mapping (uint => BlockInformation) internal myblocks;

    // hash of the block with the highest score, i.e. most work put into it (tip of the blockchain)
    uint internal bestBlockHash;

    // highest score among all blocks (so far); tip of the blockchain's score
    uint private highScore;

    // network that the stored blocks belong to
    Network private net;

    // blocks with "on hold" scrypt hash verification
    mapping (uint => BlockInformation) internal onholdBlocks;

    // counter for next on-hold block
    uint internal onholdIdx;

    // Scrypt checker
    IScryptChecker public scryptChecker;

    // TODO: Make event parameters indexed so we can register filters on them
    event StoreHeader(bytes32 blockHash, uint returnCode);
    event GetHeader(bytes32 blockHash, uint returnCode);
    event VerifyTransaction(bytes32 txHash, uint returnCode);
    event RelayTransaction(bytes32 txHash, uint returnCode);

    // @dev - the constructor
    // @param _network - Dogecoin network whose blocks DogeRelay is receiving (either mainnet or testnet).
    // It cannot be changed later.
    function DogeRelay(Network _network) public {
        // gasPriceAndChangeRecipientFee in incentive.se
        // TODO incentive management
        // self.gasPriceAndChangeRecipientFee = 50 * 10**9 * BYTES_16 // 50 shannon and left-align
        net = _network;
    }

    // @dev - sets ScryptChecker instance associated with this DogeRelay contract.
    // Once scryptChecker has been set, it cannot be changed.
    // An address of 0x0 means scryptChecker hasn't been set yet.
    //
    // @param _scryptChecker - address of the ScryptChecker contract to be associated with DogeRelay
    function setScryptChecker(address _scryptChecker) public {
        require(address(scryptChecker) == 0x0 && _scryptChecker != 0x0);
        scryptChecker = IScryptChecker(_scryptChecker);
    }

    // @dev - setInitialParent can only be called once and allows testing of storing
    // arbitrary headers and verifying/relaying transactions,
    // say from block 1.900.000, instead of genesis block
    //
    // setInitialParent should be called using a real block on the Dogecoin blockchain.
    // http://bitcoin.stackexchange.com/questions/26869/what-is-chainwork
    // chainWork can be computed using test/script.chainwork.py or
    // https://chainquery.com/bitcoin-api/getblock or local dogecoind
    //
    // Note: If used to store the imaginary block before Dogecoin's
    // genesis, then it should be called as setInitialParent(0, 0, 1) and
    // means that getBestBlockHeight() and getChainWork() will be
    // 1 more than the usual: eg Dogecoin's genesis has height 1 instead of 0
    // setInitialParent(0, 0, 1) is only for testing purposes and a TransactionFailed
    // error will happen when the first block divisible by 2016 is reached, because
    // difficulty computation requires looking up the 2016th parent, which will
    // NOT exist with setInitialParent(0, 0, 1) (only the 2015th parent exists)
    //
    // @param _blockHash - SHA-256 hash of the block being stored
    // @param _height = block's height on the Dogecoin blockchain
    // @param _chainWork - amount of work put into Dogecoin blockchain when this block was created
    function setInitialParent(uint _blockHash, uint64 _height, uint128 _chainWork) public returns (bool) {
        // reuse highScore as the flag for whether setInitialParent() has already been called

        if (highScore != 0) {
            return false;
        } else {
            highScore = 1;  // matches the score that is set below in this function
        }

        // TODO: check height > 145000, that is when Digishield was activated. The problem is that is only for production

        bestBlockHash = _blockHash;

        // height cannot be set to -1 because inMainChain() assumes that
        // a block with height 0 does NOT exist (thus we cannot allow the
        // real genesis block to be at height 0)
        m_setHeight(_blockHash, _height);

        // do NOT pass _chainWork of 0, since score 0 means
        // block does NOT exist. see check in storeBlockHeader()
        m_setScore(_blockHash, _chainWork);

        // other fields do not need to be set, for example:
        // _ancestor can remain zeros because internalBlock[0] already points to blockHash

        return true;
    }

    // @dev - Where the header begins:
    // 4 bytes function ID +
    // 32 bytes pointer to header array data +
    // 32 bytes block hash
    // 32 bytes header array size.
    // To understand abi encoding, read https://medium.com/@hayeah/how-to-decipher-a-smart-contract-method-call-8ee980311603
    // Not declared constant because inline assembly would not be able to use it.
    // Declared uint so it has no offset to access it from assembly
    // store a Dogecoin block header that must be provided in bytes format 'blockHeaderBytes'
    // Callers must keep same signature since CALLDATALOAD is used to save gas.
    //
    // @param _blockHeaderBytes - raw block header bytes
    // @param _proposedScryptBlockHash - not-yet-validated scrypt hash
    // @param _truebitClaimantAddress - address of party who will be verifying scrypt hash
    // @return - 1 if the parent has been properly set, 0 otherwise
    function storeBlockHeader(bytes _blockHeaderBytes, uint _proposedScryptBlockHash, address _truebitClaimantAddress) public returns (uint) {
        // blockHash should be a function parameter in dogecoin because the hash can not be calculated onchain.
        // Code here should call the Scrypt validator contract to make sure the supplied hash of the block is correct
        // If the block is merge mined, there are 2 Scrypts functions to execute, the one that checks PoW of the litecoin block
        // and the one that checks the block hash
        if (_blockHeaderBytes.length < 80) {
            StoreHeader(bytes32(0), ERR_INVALID_HEADER);
            return 0;
        }

        ++onholdIdx;
        BlockInformation storage bi = onholdBlocks[onholdIdx];
        bi._blockHeader = parseHeaderBytes(sliceArray(_blockHeaderBytes, 0, 80));

        // we only check the target and do not do other validation (eg timestamp) to save gas
        if (flip32Bytes(_proposedScryptBlockHash) > targetFromBits(bi._blockHeader.bits)) {
            StoreHeader(bytes32(bi._blockHeader.blockHash), ERR_PROOF_OF_WORK);
            return 0;
        }

        if ((_blockHeaderBytes[1] & 0x01) != 0) { // I think this has something to do with the version. Ask!
            // Merge mined block
            scryptChecker.checkScrypt(sliceArray(_blockHeaderBytes, _blockHeaderBytes.length - 80, _blockHeaderBytes.length), bytes32(_proposedScryptBlockHash), _truebitClaimantAddress, bytes32(onholdIdx)); //sliceArray(...) is a merge mined block header, therefore longer than a regular block header
        } else {
            // Normal block
            scryptChecker.checkScrypt(sliceArray(_blockHeaderBytes, 0, 80), bytes32(_proposedScryptBlockHash), _truebitClaimantAddress, bytes32(onholdIdx)); //For normal blocks, we just need to slice the first 80 bytes
        }

        return 1;
    }

    // @dev - once a pending block's scrypt hash has been verified as correct, this function is executed as a callback.
    // Checks whether:
    //      - it is valid to store the pending block at all (i.e. there's a parent block
    //        and the pending block hasn't already been submitted)
    //      - the block's difficulty is correct
    // If these checks pass, it stores the pending block in `myblocks` and updates high score if it becomes the new chain tip.
    //
    // @param _proposalId - request identifier of the call
    // @return - newly stored block's height if all checks pass, 0 otherwise.
    function scryptVerified(bytes32 _proposalId) public returns (uint) {
        if (msg.sender != address(scryptChecker)) {
            StoreHeader(bytes32(0), ERR_INVALID_HEADER);
            return 0;
        }

        BlockInformation storage bi = onholdBlocks[uint(_proposalId)];

        uint blockSha256Hash = bi._blockHeader.blockHash;

        uint hashPrevBlock = bi._blockHeader.prevBlock;

        uint128 scorePrevBlock = m_getScore(hashPrevBlock);

        if (scorePrevBlock == 0) {
            StoreHeader(bytes32(blockSha256Hash), ERR_NO_PREV_BLOCK);
            return 0;
        }

        if (m_getScore(blockSha256Hash) != 0) {
            // block already stored/exists
            StoreHeader(bytes32(blockSha256Hash), ERR_BLOCK_ALREADY_EXISTS);
            return 0;
        }

        uint32 bits = bi._blockHeader.bits;

        uint blockHeight = 1 + m_getHeight(hashPrevBlock);
        uint32 prevBits = m_getBits(hashPrevBlock);

        // Ignore difficulty adjustment verification for regtest until we implement it
        if (net != Network.REGTEST) {
            if (ibIndex == 0) {
                // since blockHeight is 1 more than blockNumber; OR clause is special case for 1st header
                // we need to check prevBits isn't 0 otherwise the 1st header
                // will always be rejected (since prevBits doesn't exist for the initial parent)
                // This allows blocks with arbitrary difficulty from being added to
                // the initial parent, but as these forks will have lower score than
                // the main chain, they will not have impact.
                if (bits != prevBits && prevBits != 0) {
                    StoreHeader(bytes32(blockSha256Hash), ERR_DIFFICULTY);
                    return 0;
                }
            } else if (ibIndex == 1) {
                // In order to avoid the 'grandparent block bug', we don't check anything
                // for the 2nd stored block now. This should be implemented later!!!

            } else {
                // (blockHeight - DIFFICULTY_ADJUSTMENT_INTERVAL) is same as [getHeight(hashPrevBlock) - (DIFFICULTY_ADJUSTMENT_INTERVAL - 1)]

                uint32 newBits = calculateDigishieldDifficulty(int64(m_getTimestamp(hashPrevBlock)) - int64(m_getTimestamp(getPrevBlock(hashPrevBlock))), prevBits);

                if (net == Network.TESTNET && bi._blockHeader.time - m_getTimestamp(hashPrevBlock) > 120 && blockHeight >= 157500) {
                    newBits = 0x1e0fffff;
                }

                // Difficulty adjustment verification
                if (bits != newBits && newBits != 0) {  // newBits != 0 to allow first header
                    StoreHeader(bytes32(blockSha256Hash), ERR_RETARGET);
                    return 0;
                }
            }
        }

        myblocks[blockSha256Hash] = bi;
        m_saveAncestors(blockSha256Hash, hashPrevBlock);  // increments ibIndex

        delete onholdBlocks[uint(_proposalId)];

        // https://en.bitcoin.it/wiki/Difficulty
        // Min difficulty for bitcoin is 0x1d00ffff
        //uint128 scoreBlock = scorePrevBlock + uint128 (0x00000000FFFF0000000000000000000000000000000000000000000000000000 / target);
        // Min difficulty for dogecoin is 0x1e0fffff
        uint128 scoreBlock = scorePrevBlock + uint128 (0x00000FFFFF000000000000000000000000000000000000000000000000000000 / targetFromBits(bits));
        //log2(bytes32(scoreBlock), bytes32(bits), bytes32(target));
        // bitcoinj (so libdohj, dogecoin java implemntation) uses 2**256 as a dividend.
        // Investigate: May dogerelay best block be different than libdohj best block in some border cases?
        // Does libdohj matches dogecoin core?
        m_setScore(blockSha256Hash, scoreBlock);

        // equality allows block with same score to become an (alternate) Tip, so that
        // when an (existing) Tip becomes stale, the chain can continue with the alternate Tip
        if (scoreBlock >= highScore) {
            bestBlockHash = blockSha256Hash;
            highScore = scoreBlock;
        }

        StoreHeader(bytes32(blockSha256Hash), blockHeight);
        return blockHeight;
    }

    // @dev - Implementation of DigiShield, almost directly translated from
    // C++ implementation of Dogecoin. See function CalculateDogecoinNextWorkRequired
    // on dogecoin/src/dogecoin.cpp for more details.
    // Calculates the next block's difficulty based on the current block's elapsed time
    // and the desired mining time for a block, which is 60 seconds after block 145k.
    //
    // @param _actualTimespan - time elapsed from previous block creation til current block creation;
    // i.e., how much time it took to mine the current block
    // @param _bits - previous block header difficulty (in bits)
    // @return - expected difficulty for the next block
    function calculateDigishieldDifficulty(int64 _actualTimespan, uint32 _bits) private returns (uint32 result) {
        int64 retargetTimespan = int64(TARGET_TIMESPAN);
        int64 nModulatedTimespan = int64(_actualTimespan);

        nModulatedTimespan = retargetTimespan + int64(nModulatedTimespan - retargetTimespan) / int64(8); //amplitude filter
        int64 nMinTimespan = retargetTimespan - (int64(retargetTimespan) / int64(4));
        int64 nMaxTimespan = retargetTimespan + (int64(retargetTimespan) / int64(2));

        // Limit adjustment step
        if (nModulatedTimespan < nMinTimespan) {
            nModulatedTimespan = nMinTimespan;
        } else if (nModulatedTimespan > nMaxTimespan) {
            nModulatedTimespan = nMaxTimespan;
        }

        // Retarget
        uint bnNew = targetFromBits(_bits);
        bnNew = bnNew * uint(nModulatedTimespan);
        bnNew = uint(bnNew) / uint(retargetTimespan);

        if (bnNew > POW_LIMIT) {
            bnNew = POW_LIMIT;
        }

        return m_toCompactBits(bnNew);
    }

    uint constant HASH_SIZE = 32;

    // @dev - store a number of blockheaders by calling storeBlockHeader multiple times.
    // Return latest's block height
    //
    // @param _headersBytes - Dogecoin block headers, all concatenated together and encoding in the following format:
    //      - header size (4 bytes, big-endian representation)
    //      - actual header (size is variable.)
    // @param _hashesBytes - concatenated scrypt hashes corresponding to concatenated headers;
    // _hashesBytes[i] should be _headersBytes[i]'s scrypt hash
    // @param count - number of headers sent
    // @return - height of last stored block
    function bulkStoreHeaders(bytes _headersBytes, bytes _hashesBytes, uint count, address truebitClaimantAddress) public returns (uint result) {
        //uint8 HEADER_SIZE = 80;
        uint headersOffset = 0;
        uint headersEndIndex = 4;
        uint hashesOffset = 0;
        uint hashesEndIndex = HASH_SIZE;
        uint i = 0;
        while (i < count) {
            uint currHeaderLength = bytesToUint32(sliceArray(_headersBytes, headersOffset, headersEndIndex));
            headersOffset += 4;
            headersEndIndex += currHeaderLength;
            //log2(bytes32(currHeaderLength), bytes32(headersOffset), bytes32(headersEndIndex));
            result = storeBlockHeader(sliceArray(_headersBytes, headersOffset, headersEndIndex), uint(bytesToBytes32(sliceArray(_hashesBytes, hashesOffset, hashesEndIndex))), truebitClaimantAddress);
            headersOffset += currHeaderLength;
            headersEndIndex += 4;
            hashesOffset += HASH_SIZE;
            hashesEndIndex += HASH_SIZE;
            i += 1;
        }

        // If bytes[] function parameter would work
        //for (uint i = 0; i < _headersBytes.length; i++) {
        //      result = storeBlockHeader(headers[i], hashes[i]);
        //}
    }

    // @dev - Converts a bytes of size 4 to uint32,
    // e.g. for input [0x01, 0x02, 0x03 0x04] returns 0x01020304
    function bytesToUint32(bytes memory input) internal pure returns (uint32 result) {
        result = uint32(input[0])*(2**24) + uint32(input[1])*(2**16) + uint32(input[2])*(2**8) + uint32(input[3]);
    }

    // @dev - Checks whether the transaction given by `_txBytes` is in the block identified by `_txBlockHash`.
    // First it guards against a Merkle tree collision attack by raising an error if the transaction is exactly 64 bytes long,
    // then it calls helperVerifyHash__ to do the actual check.
    //
    // @param _txBytes - transaction bytes
    // @param _txIndex - transaction's index within the block
    // @param _siblings - transaction's Merkle siblings
    // @param _txBlockHash - hash of the block that might contain the transaction
    // @return - SHA-256 hash of _txBytes if the transaction is in the block, 0 otherwise 
    function verifyTx(bytes _txBytes, uint _txIndex, uint[] _siblings, uint _txBlockHash) public returns (uint) {
        uint txHash = m_dblShaFlip(_txBytes);
        
        if (_txBytes.length == 64) {  // todo: is check 32 also needed?
            VerifyTransaction(bytes32(txHash), ERR_TX_64BYTE);
            return 0;
        }

        if (helperVerifyHash__(txHash, _txIndex, _siblings, _txBlockHash) == 1) {
            return txHash;
        } else {
            // log is done via helperVerifyHash__
            return 0;
        }
    }

    // @dev - Checks whether the transaction identified by `_txHash` is in the block identified by `_txBlockHash`
    // and whether the block is in Dogecoin's main chain. Transaction check is done via Merkle proof.
    // Note: no verification is performed to prevent txHash from just being an
    // internal hash in the Merkle tree. Thus this helper method should NOT be used
    // directly and is intended to be private.
    //
    // @param _txHash - transaction hash
    // @param _txIndex - transaction's index within the block
    // @param _siblings - transaction's Merkle siblings
    // @param _txBlockHash - hash of the block that might contain the transaction
    // @return - 1 if the transaction is in the block and the block is in the main chain,
    // 20020 (ERR_CONFIRMATIONS) if the block is not in the main chain,
    // 20040 (ERR_MERKLE_ROOT) if the block is in the main chain but the Merkle proof fails.
    function helperVerifyHash__(uint256 _txHash, uint _txIndex, uint[] _siblings, uint _txBlockHash) private returns (uint) {
        // TODO: implement when dealing with incentives
        // if (!feePaid(_txBlockHash, m_getFeeAmount(_txBlockHash))) {  // in incentive.se
        //    VerifyTransaction(bytes32(_txHash), ERR_BAD_FEE);
        //    return (ERR_BAD_FEE);
        // }

        if (within6Confirms(_txBlockHash)) {
            VerifyTransaction(bytes32(_txHash), ERR_CONFIRMATIONS);
            return (ERR_CONFIRMATIONS);
        }

  //      if (!priv_inMainChain__(_txBlockHash)) {
  //          VerifyTransaction(bytes32(_txHash), ERR_CHAIN);
  //          return (ERR_CHAIN);
  //      }

        if (computeMerkle(_txHash, _txIndex, _siblings) != getMerkleRoot(_txBlockHash)) {
          VerifyTransaction(bytes32(_txHash), ERR_MERKLE_ROOT);
          return (ERR_MERKLE_ROOT);
        }

        VerifyTransaction(bytes32(_txHash), 1);
        return (1);
    }

    // @dev - relays transaction `_txBytes` to `_targetContract`'s processTransaction() method.
    // Also logs the value of processTransaction.
    // Note: callers cannot be 100% certain when an ERR_RELAY_VERIFY occurs because
    // it may also have been returned by processTransaction(). Callers should be
    // aware of the contract that they are relaying transactions to and
    // understand what that contract's processTransaction method returns.
    //
    // @param _txHash - transaction hash
    // @param _txIndex - transaction's index within the block
    // @param _siblings - transaction's Merkle siblings
    // @param _txBlockHash - hash of the block that might contain the transaction
    // @param _targetContract - 
    // @return - return value of processTransaction() if _txHash is in the block identified by _txBlockHash,
    // ERR_RELAY_VERIFY return code otherwise
    function relayTx(bytes _txBytes, uint _txIndex, uint[] _siblings, uint _txBlockHash, TransactionProcessor _targetContract) public returns (uint) {
        uint txHash = verifyTx(_txBytes, _txIndex, _siblings, _txBlockHash);
        if (txHash != 0) {
            uint returnCode = _targetContract.processTransaction(_txBytes, txHash);
            RelayTransaction(bytes32(txHash), returnCode);
            return (returnCode);
        }

        RelayTransaction(bytes32(0), ERR_RELAY_VERIFY);
        return(ERR_RELAY_VERIFY);
    }

    // @dev - Returns a list of block hashes (9 hashes maximum) that helps an agent find out what
    // doge blocks DogeRelay is missing.
    // The first position contains bestBlock, then bestBlock-5, then bestBlock-25 ... until bestBlock-78125
    //
    // @return - list of up to 9 ancestor block hashes
    function getBlockLocator() public view returns (uint[9] locator) {
        uint blockHash = bestBlockHash;
        //locator.push(blockHash);
        locator[0] = blockHash;
        for (uint i = 0 ; i < NUM_ANCESTOR_DEPTHS ; i++) {
            // uint blockHash2 = internalBlock[m_getAncestor(blockHash, i)];
            //if (blockHash2 != 0) {
            //    locator.push(blockHash2);
            //}
            locator[i+1] = internalBlock[m_getAncestor(blockHash, i)];
        }
        return locator;
    }

    // @dev - return the height of the best block (chain tip)
    function getBestBlockHeight() public view returns (uint) {
        return m_getHeight(bestBlockHash);
    }

    // @dev - return the hash of the best block (chain tip)
    function getBestBlockHash() public view returns (uint) {
        return bestBlockHash;
    }

    // @dev - save the ancestors for a block, as well as updating the height
    // note: this is internal/private
    //
    // @param _blockHash - hash of the block whose ancestors are being saved
    // @param _hashPrevBlock - hash of its parent block
    function m_saveAncestors(uint _blockHash, uint _hashPrevBlock) private {
        internalBlock[ibIndex] = _blockHash;
        m_setIbIndex(_blockHash, ibIndex);
        ibIndex += 1;

        m_setHeight(_blockHash, m_getHeight(_hashPrevBlock) + 1);

        // 8 indexes into internalBlock can be stored inside one ancestor (32 byte) word
        uint ancWord = 0;

        // the first ancestor is the index to _hashPrevBlock, and write it to ancWord
        uint32 prevIbIndex = m_getIbIndex(_hashPrevBlock);
        ancWord = m_mwrite32(ancWord, 0, prevIbIndex);

        uint blockHeight = m_getHeight(_blockHash);

        // update ancWord with the remaining indexes
        for (uint i = 1 ; i < NUM_ANCESTOR_DEPTHS ; i++) {
            if (blockHeight % m_getAncDepth(i) == 1) {
                ancWord = m_mwrite32(ancWord, 4*i, prevIbIndex);
            } else {
                ancWord = m_mwrite32(ancWord, 4*i, m_getAncestor(_hashPrevBlock, i));
            }
        }
        //log1(bytes32(_blockHash), bytes32(ancWord));

        // write the ancestor word to storage
        myblocks[_blockHash]._ancestor = ancWord;
    }


    // @dev - private (to prevent leeching)
    // Checks if a given block is in main Dogecoin chain
    //
    // @param _blockHash - hash of the block being searched for in the main chain
    // @return - true if the block identified by _blockHash is in the main chain,
    // false otherwise
    function priv_inMainChain__(uint _blockHash) private view returns (bool) {
        require(msg.sender == address(this));

        uint blockHeight = m_getHeight(_blockHash);

        // By assuming that a block with height 0 does not exist, we can do
        // this optimization and immediate say that _blockHash is not in the main chain.
        // However, the consequence is that
        // the genesis block must be at height 1 instead of 0 [see setInitialParent()]
        if (blockHeight == 0) {
          return false;
        }

        return (priv_fastGetBlockHash__(blockHeight) == _blockHash);
    }

    // @dev - private (to prevent leeching)
    // callers must ensure 2 things:
    // * _blockHeight is greater than 0 (otherwise infinite loop since
    // minimum height is 1)
    // * _blockHeight is less than the height of bestBlockHash, otherwise the
    // bestBlockHash is returned
    //
    // @param _blockHeight - block height
    // @return - hash corresponding to block of height _blockHeight
    function priv_fastGetBlockHash__(uint _blockHeight) internal view returns (uint) {
        //Comment out require to make tests work
        //require(msg.sender == address(this));

        uint blockHash = bestBlockHash;
        uint anc_index = NUM_ANCESTOR_DEPTHS - 1;

        while (m_getHeight(blockHash) > _blockHeight) {
            while (m_getHeight(blockHash) - _blockHeight < m_getAncDepth(anc_index) && anc_index > 0) {
                anc_index -= 1;
            }
            blockHash = internalBlock[m_getAncestor(blockHash, anc_index)];
        }

        return blockHash;
    }

    // @dev - a block's _ancestor storage slot contains 8 indexes into internalBlock, so
    // this function returns the index that can be used to look up the desired ancestor
    // e.g. for combined usage, internalBlock[m_getAncestor(someBlock, 2)] will
    // return the block hash of someBlock's 3rd ancestor
    //
    // @param _blockHash - hash of the block whose ancestor is being looked up
    // @param _whichAncestor - index of ancestor to be looked up; an integer between 0 and 7 where 0 is the given block's parent
    // @return - desired ancestor's hash
    function m_getAncestor(uint _blockHash, uint _whichAncestor) private view returns (uint32) {
        return uint32 ((myblocks[_blockHash]._ancestor * (2**(32*uint(_whichAncestor)))) / BYTES_28);
    }

    // dev - returns depth associated with an ancestor index; applies to any block
    //
    // @param _index - index of ancestor to be looked up; an integer between 0 and 7
    // @return - depth corresponding to said index, i.e. 5**index
    function m_getAncDepth(uint _index) private pure returns (uint) {
        return 5**(uint(_index));
    }

    // @dev - write `_eightBytes` into `_word` starting from `_position`
    // This is useful for writing 64bit ints inside one 32 byte word
    //
    // @param _word - information to be partially overwritten
    // @param _position - position to start writing from
    // @param _eightBytes - information to be written
    function m_mwrite64(uint _word, uint8 _position, uint64 _eightBytes) private pure returns (uint) {
        // Store uint in a struct wrapper because that is the only way to get a pointer to it
        UintWrapper memory uw = UintWrapper(_word);
        uint pointer = ptr(uw);
        assembly {
            mstore8(add(pointer, _position        ), byte(24, _eightBytes))
            mstore8(add(pointer, add(_position, 1)), byte(25, _eightBytes))
            mstore8(add(pointer, add(_position, 2)), byte(26, _eightBytes))
            mstore8(add(pointer, add(_position, 3)), byte(27, _eightBytes))
            mstore8(add(pointer, add(_position, 4)), byte(28, _eightBytes))
            mstore8(add(pointer, add(_position, 5)), byte(29, _eightBytes))
            mstore8(add(pointer, add(_position, 6)), byte(30, _eightBytes))
            mstore8(add(pointer, add(_position, 7)), byte(31, _eightBytes))
        }
        return uw.value;
    }

    // @dev - write `_eightBytes` into `_word` starting from `_position`
    // This is useful for writing 128bit ints inside one 32 byte word
    //
    // @param _word - information to be partially overwritten
    // @param _position - position to start writing from
    // @param _eightBytes - information to be written
    function m_mwrite128(uint _word, uint8 _position, uint128 _sixteenBytes) private pure returns (uint) {
        // Store uint in a struct wrapper because that is the only way to get a pointer to it
        UintWrapper memory uw = UintWrapper(_word);
        uint pointer = ptr(uw);
        assembly {
            mstore8(add(pointer, _position         ),  byte(16, _sixteenBytes))
            mstore8(add(pointer, add(_position,  1)),  byte(17, _sixteenBytes))
            mstore8(add(pointer, add(_position,  2)),  byte(18, _sixteenBytes))
            mstore8(add(pointer, add(_position,  3)),  byte(19, _sixteenBytes))
            mstore8(add(pointer, add(_position,  4)),  byte(20, _sixteenBytes))
            mstore8(add(pointer, add(_position,  5)),  byte(21, _sixteenBytes))
            mstore8(add(pointer, add(_position,  6)),  byte(22, _sixteenBytes))
            mstore8(add(pointer, add(_position,  7)),  byte(23, _sixteenBytes))
            mstore8(add(pointer, add(_position,  8)),  byte(24, _sixteenBytes))
            mstore8(add(pointer, add(_position,  9)),  byte(25, _sixteenBytes))
            mstore8(add(pointer, add(_position,  10)), byte(26, _sixteenBytes))
            mstore8(add(pointer, add(_position,  11)), byte(27, _sixteenBytes))
            mstore8(add(pointer, add(_position,  12)), byte(28, _sixteenBytes))
            mstore8(add(pointer, add(_position,  13)), byte(29, _sixteenBytes))
            mstore8(add(pointer, add(_position,  14)), byte(30, _sixteenBytes))
            mstore8(add(pointer, add(_position,  15)), byte(31, _sixteenBytes))
        }
        return uw.value;
    }

    // @dev - write `_fourBytes` into `_word` starting from `_position`
    // This is useful for writing 32bit ints inside one 32 byte word
    //
    // @param _word - information to be partially overwritten
    // @param _position - position to start writing from
    // @param _eightBytes - information to be written
    function m_mwrite32(uint _word, uint _position, uint32 _fourBytes) private pure returns (uint) {
        // Store uint in a struct wrapper because that is the only way to get a pointer to it
        UintWrapper memory uw = UintWrapper(_word);
        uint pointer = ptr(uw);
        assembly {
            mstore8(add(pointer, _position), byte(28, _fourBytes))
            mstore8(add(pointer, add(_position,1)), byte(29, _fourBytes))
            mstore8(add(pointer, add(_position,2)), byte(30, _fourBytes))
            mstore8(add(pointer, add(_position,3)), byte(31, _fourBytes))
        }
        return uw.value;
    }

    // @dev converts bytes of any length to bytes32.
    // If `_rawBytes` is longer than 32 bytes, it truncates to the 32 leftmost bytes.
    // If it is shorter, it pads with 0s on the left.
    // Should be private, made internal for testing
    //
    // @param _rawBytes - arbitrary length bytes
    // @return - leftmost 32 or less bytes of input value; padded if less than 32
    function bytesToBytes32(bytes _rawBytes) internal pure returns (bytes32) {
        bytes32 out;
        for (uint i = 0; i < 32; i++) {
            out |= bytes32(_rawBytes[i]) >> (i * 8);
        }
        return out;
    }

    // @dev returns a portion of a given byte array specified by its starting and ending points
    // Should be private, made internal for testing
    // Breaks underscore naming convention for parameters because it raises a compiler error
    // if `offset` is changed to `_offset`.
    //
    // @param _rawBytes - array to be sliced
    // @param offset - first byte of sliced array
    // @param _endIndex - last byte of sliced array
    function sliceArray(bytes memory _rawBytes, uint offset, uint _endIndex) internal view returns (bytes) {
        uint len = _endIndex - offset;
        bytes memory result = new bytes(len);
        assembly {
            // Call precompiled contract to copy data
            if iszero(call(not(0), 0x04, 0, add(add(_rawBytes, 0x20), offset), len, add(result, 0x20), len)) {
                revert(0, 0)
            }
        }
        return result;
    }

    // @dev - converts raw bytes representation of a Dogecoin block header to struct representation
    //
    // @param _rawBytes - first 80 bytes of a block header
    // @return - exact same header information in BlockHeader struct form
    function parseHeaderBytes(bytes _rawBytes) internal returns (BlockHeader bh) {
        bh.version = f_version(_rawBytes);
        bh.time = f_getTimestamp(_rawBytes);
        bh.bits = f_bits(_rawBytes);
        bh.blockHash = m_dblShaFlip(_rawBytes);
        bh.prevBlock = f_hashPrevBlock(_rawBytes);
        bh.merkleRoot = f_merkleRoot(_rawBytes);
    }

    // @dev - For a valid proof, returns the root of the Merkle tree.
    //
    // @param _txHash - transaction hash
    // @param _txIndex - transaction's index within the block it's assumed to be in
    // @param _siblings - transaction's Merkle siblings
    // @return - Merkle tree root of the block the transaction belongs to if the proof is valid,
    // garbage if it's invalid
    function computeMerkle(uint _txHash, uint _txIndex, uint[] _siblings) private pure returns (uint) {
        uint resultHash = _txHash;
        // uint proofLen = _siblings.length;
        uint i = 0;
        while (i < _siblings.length) {
            uint proofHex = _siblings[i];

            uint sideOfSiblings = _txIndex % 2;  // 0 means _siblings is on the right; 1 means left

            uint left;
            uint right;
            if (sideOfSiblings == 1) {
                left = proofHex;
                right = resultHash;
            } else if (sideOfSiblings == 0) {
                left = resultHash;
                right = proofHex;
            }

            resultHash = concatHash(left, right);

            _txIndex /= 2;
            i += 1;
        }

        return resultHash;
    }

    // @dev - checks whether the block identified by _blockHash is within 6 blocks of the chain's best block
    //
    // @param _blockHash - block hash
    // @return - true if the block is within 6 blocks of the chain's best block,
    // false if it is not within 6 blocks or the hash does not exist in the chain
    function within6Confirms(uint _blockHash) private view returns (bool) {
        uint blockHash = bestBlockHash;
        uint i = 0;
        while (i < 6) {
            if (_blockHash == blockHash) {
                return true;
            }
            // blockHash = self.block[blockHash]._prevBlock
            blockHash = getPrevBlock(blockHash);
            i += 1;
        }
        return false;
    }

    // @dev - Convert uint256 to compact encoding
    // based on https://github.com/petertodd/python-bitcoinlib/blob/2a5dda45b557515fb12a0a18e5dd48d2f5cd13c2/bitcoin/core/serialize.py
    // Analogous to arith_uint256::GetCompact from C++ implementation
    //
    // @param _val - difficulty in target format
    // @return - difficulty in bits format
    function m_toCompactBits(uint _val) private pure returns (uint32) {
        uint nbytes = uint (m_shiftRight((m_bitLen(_val) + 7), 3));
        uint32 compact = 0;
        if (nbytes <= 3) {
            compact = uint32 (m_shiftLeft((_val & 0xFFFFFF), 8 * (3 - nbytes)));
        } else {
            compact = uint32 (m_shiftRight(_val, 8 * (nbytes - 3)));
            compact = uint32 (compact & 0xFFFFFF);
        }

        // If the sign bit (0x00800000) is set, divide the mantissa by 256 and
        // increase the exponent to get an encoding without it set.
        if ((compact & 0x00800000) > 0) {
            compact = uint32(m_shiftRight(compact, 8));
            nbytes += 1;
        }

        return compact | uint32(m_shiftLeft(nbytes, 24));
    }

    // @dev - get the block hash of a Dogecoin block's parent
    //
    // @param _blockHash - hash of the block whose parent is to be returned
    // @return - hash of `_blockHash`'s parent block in big-endian format
    function getPrevBlock(uint _blockHash) internal view returns (uint) {
        return myblocks[_blockHash]._blockHeader.prevBlock;
    }

    // @dev - get the timestamp from a Dogecoin block header
    // @param _blockHash - hash of the block whose timestamp is to be returned
    // @return - block's timestamp in big-endian format
    function m_getTimestamp(uint _blockHash) internal view returns (uint32 result) {
        return myblocks[_blockHash]._blockHeader.time;
     }

    // @dev - get difficulty (in bits format) from a Dogecoin block header
    // @param _blockHash - hash of the block whose difficulty is to be returned
    // @return - block's bits in big-endian format
    function m_getBits(uint _blockHash) internal view returns (uint32 result) {
        return myblocks[_blockHash]._blockHeader.bits;        
    }

    // @dev - get the merkle root of '$_blockHash'
    // @param _blockHash - hash of the block whose Merkle root is to be returned
    // @return block's Merkle root in big-endian format
    function getMerkleRoot(uint _blockHash) private view returns (uint) {
        return myblocks[_blockHash]._blockHeader.merkleRoot;        
    }

    // @dev - Bitcoin-way of hashing
    // @param _dataBytes - raw data to be hashed
    // @return - result of applying SHA-256 twice to raw data and then flipping the bytes
    function m_dblShaFlip(bytes _dataBytes) private pure returns (uint) {
        return flip32Bytes(uint(sha256(sha256(_dataBytes))));
    }

    // @dev - Bitcoin-way of computing the target from the 'bits' field of a block header
    // based on http://www.righto.com/2014/02/bitcoin-mining-hard-way-algorithms.html//ref3
    //
    // @param _bits - difficulty in bits format
    // @return - difficulty in target format
    function targetFromBits(uint32 _bits) internal pure returns (uint) {
        uint exp = _bits / 0x1000000;  // 2**24
        uint mant = _bits & 0xffffff;
        return mant * 256**(exp - 3);
    }

    // @dev - Helper function for Merkle root calculation.
    // Given two sibling nodes in a Merkle tree, calculate their parent.
    // Concatenates hashes `_tx1` and `_tx2`, then hashes the result.
    //
    // @param _tx1 - Merkle node (either root or internal node)
    // @param _tx2 - Merkle node (either root or internal node), has to be `_tx1`'s sibling
    // @return - `_tx1` and `_tx2`'s parent, i.e. the result of concatenating them,
    // hashing that twice and flipping the bytes.
    function concatHash(uint _tx1, uint _tx2) internal pure returns (uint) {
        return flip32Bytes(uint(sha256(sha256(flip32Bytes(_tx1), flip32Bytes(_tx2)))));
    }

    // @dev - shift information to the right by a specified number of bits
    //
    // @param _val - value to be shifted
    // @param _shift - number of bits to shift
    // @return - `_val` shifted `_shift` bits to the right, i.e. divided by 2**`_shift`
    function m_shiftRight(uint _val, uint _shift) private pure returns (uint) {
        return _val / uint(2)**_shift;
    }

    // @dev - shift information to the left by a specified number of bits
    //
    // @param _val - value to be shifted
    // @param _shift - number of bits to shift
    // @return - `_val` shifted `_shift` bits to the left, i.e. multiplied by 2**`_shift`
    function m_shiftLeft(uint _val, uint _shift) private pure returns (uint) {
        return _val * uint(2)**_shift;
    }

    // @dev - get the number of bits required to represent a given integer value without losing information
    //
    // @param _val - unsigned integer value
    // @return - given value's bit length
    function m_bitLen(uint _val) private pure returns (uint length) {
        uint int_type = _val;
        while (int_type > 0) {
          int_type = m_shiftRight(int_type, 1);
          length += 1;
        }
    }

    // @dev - convert an unsigned integer from little-endian to big-endian representation
    //
    // @param _input - little-endian value
    // @return - input value in big-endian format
    function flip32Bytes(uint _input) internal pure returns (uint) {
        uint i = 0;
        // unrolling this would decrease gas usage, but would increase
        // the gas cost for code size by over 700K and exceed the PI million block gas limit
        UintWrapper memory uw = UintWrapper(0);
        uint pointer = ptr(uw);
        while (i < 32) {
            assembly {
                mstore8(add(pointer, i), byte(sub(31 ,i), _input))
            }
            i++;
        }
        return uw.value;
    }

    //
    //  function accessors for a block's _info (height, ibIndex, score)
    //

    // @dev set `_blockHash`'s height to `_blockHeight` within `myblocks` mapping
    // block height is the first 8 bytes of _info
    //
    // @param _blockHash - hash of the block whose height is to be set
    // @param _blockHeight - value that the height is being set to
    function m_setHeight(uint _blockHash, uint64 _blockHeight) private {
        uint info = myblocks[_blockHash]._info;
        info = m_mwrite64(info, 0, _blockHeight);
        myblocks[_blockHash]._info = info;
    }

    // @dev return a block's height
    //
    // @param _blockHash - hash identifying the block
    // @result - height of the block identified by `_blockHash`
    function m_getHeight(uint _blockHash) internal view returns (uint64) {
        return uint64(myblocks[_blockHash]._info / BYTES_24);
    }

    // @dev - ibIndex is the index to self.internalBlock: it's the second 8 bytes of _info
    // This function is used within saveAncestors.
    //
    // @param _blockHash - hash of the block whose internal index is to be set
    // @param _internalIndex - value that the index is being set to;
    // required to be DogeRelay's internal block index at the time it is called
    function m_setIbIndex(uint _blockHash, uint32 _internalIndex) private {
        uint info = myblocks[_blockHash]._info;
        uint64 internalIndex64 = _internalIndex;
        info = m_mwrite64(info, 8, internalIndex64);
        myblocks[_blockHash]._info = info;
    }

    // @dev - get internal index for a given block
    //
    // @param _blockHash - hash identifying the block
    // @result - internal index of the block identified by `_blockHash`
    function m_getIbIndex(uint _blockHash) private view returns (uint32) {
        return uint32(myblocks[_blockHash]._info * BYTES_8 / BYTES_24);
    }

    // @dev - set a given block's score, i.e. the amount of work put into it
    // score of the block is the last 16 bytes of _info
    //
    // @param _blockHash - hash of the block whose work is to be set
    // @param _blockScore - work that has been put into the block
    function m_setScore(uint _blockHash, uint128 _blockScore) private {
        uint info = myblocks[_blockHash]._info;
        info = m_mwrite128(info, 16, _blockScore);
        myblocks[_blockHash]._info = info;
    }

    // @dev - get work/score for a given block
    //
    // @param _blockHash - hash identifying the block
    // @result - work put into the block identified by `_blockHash`
    function m_getScore(uint _blockHash) internal view returns (uint128) {
        return uint128(myblocks[_blockHash]._info * BYTES_16 / BYTES_16);
    }

    // Util functions and wrappers to get pointers to memory and storage

    struct UintWrapper {
        uint value;
    }

    // @dev - Returns a pointer to the supplied UintWrapper
    function ptr(UintWrapper memory uw) private pure returns (uint addr) {
        assembly {
            addr := uw
        }
    }

    // @dev - Returns a pointer to the supplied BlockInformation
    function ptr(BlockInformation storage bi) private pure returns (uint addr) {
        assembly {
            addr := bi_slot
        }
    }

    // @dev - Returns a pointer to the content of the supplied byte array in storage
    function ptr(bytes storage byteArray) private pure returns (uint addr) {
        uint pointer;
        assembly {
            pointer := byteArray_slot
        }
        addr = uint(keccak256(bytes32(pointer)));
    }

    // 0x00 version
    // 0x04 prev block hash
    // 0x24 merkle root
    // 0x44 timestamp
    // 0x48 bits
    // 0x4c nonce

    // @dev - extract version field from a raw Dogecoin block header
    //
    // @param _blockHeader - Dogecoin block header bytes
    // @return - block's version in big endian format
    function f_version(bytes memory _blockHeader) internal pure returns (uint32 version) {
        assembly {
            let word := mload(add(_blockHeader, 0x4))
            version := add(byte(24, word),
                add(mul(byte(25, word), 0x100),
                    add(mul(byte(26, word), 0x10000),
                        mul(byte(27, word), 0x1000000))))
        }
    }

    // @dev - extract previous block field from a raw Dogecoin block header
    //
    // @param _blockHeader - Dogecoin block header bytes
    // @return - hash of block's parent in big endian format
    function f_hashPrevBlock(bytes memory _blockHeader) internal pure returns (uint) {
        uint hashPrevBlock;
        assembly {
            hashPrevBlock := mload(add(_blockHeader, 0x24))
        }
        return flip32Bytes(hashPrevBlock);
    }

    // @dev - extract Merkle root field from a raw Dogecoin block header
    //
    // @param _blockHeader - Dogecoin block header bytes
    // @return - block's Merkle root in big endian format
    function f_merkleRoot(bytes _blockHeader) private view returns (uint) {
        uint merkle;
        assembly {
            merkle := mload(add(_blockHeader, 0x44))
        }
        return flip32Bytes(merkle);        
    }

    // @dev - extract bits field from a raw Dogecoin block header
    //
    // @param _blockHeader - Dogecoin block header bytes
    // @return - block's difficulty in bits format, also big-endian
    function f_bits(bytes memory _blockHeader) internal pure returns (uint32 bits) {
        assembly {
            let word := mload(add(_blockHeader, 0x50))
            bits := add(byte(24, word),
                add(mul(byte(25, word), 0x100),
                    add(mul(byte(26, word), 0x10000),
                        mul(byte(27, word), 0x1000000))))
        }
    }

    // @dev - extract timestamp field from a raw Dogecoin block header
    //
    // @param _blockHeader - Dogecoin block header bytes
    // @return - block's timestamp in big-endian format
    function f_getTimestamp(bytes memory _blockHeader) internal pure returns (uint32 time) {
        assembly {
            let word := mload(add(_blockHeader, 0x4c))
            time := add(byte(24, word),
                add(mul(byte(25, word), 0x100),
                    add(mul(byte(26, word), 0x10000),
                        mul(byte(27, word), 0x1000000))))
        }
    }

    // Constants

    // for verifying Bitcoin difficulty
    // uint constant DIFFICULTY_ADJUSTMENT_INTERVAL = 2016;  // Bitcoin adjusts every 2 weeks
    // uint constant TARGET_TIMESPAN = 14 * 24 * 60 * 60;  // 2 weeks
    // uint constant TARGET_TIMESPAN_DIV_4 = TARGET_TIMESPAN / 4;
    // uint constant TARGET_TIMESPAN_MUL_4 = TARGET_TIMESPAN * 4;
    // uint constant UNROUNDED_MAX_TARGET = 2**224 - 1;  // different from (2**16-1)*2**208 http =//bitcoin.stackexchange.com/questions/13803/how/ exactly-was-the-original-coefficient-for-difficulty-determined

    // for verifying Dogecoin difficulty
    uint constant DIFFICULTY_ADJUSTMENT_INTERVAL = 1;  // Bitcoin adjusts every block
    uint constant TARGET_TIMESPAN =  60;  // 1 minute
    uint constant TARGET_TIMESPAN_DIV_4 = TARGET_TIMESPAN / 4;
    uint constant TARGET_TIMESPAN_MUL_4 = TARGET_TIMESPAN * 4;
    uint constant UNROUNDED_MAX_TARGET = 2**224 - 1;  // different from (2**16-1)*2**208 http =//bitcoin.stackexchange.com/questions/13803/how/ exactly-was-the-original-coefficient-for-difficulty-determined
    uint constant POW_LIMIT = 0x00000fffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    //
    // Error / failure codes
    //

    // error codes for storeBlockHeader
    uint constant ERR_DIFFICULTY =  10010;  // difficulty didn't match current difficulty
    uint constant ERR_RETARGET = 10020;  // difficulty didn't match retarget
    uint constant ERR_NO_PREV_BLOCK = 10030;
    uint constant ERR_BLOCK_ALREADY_EXISTS = 10040;
    uint constant ERR_INVALID_HEADER = 10050;
    uint constant ERR_PROOF_OF_WORK = 10090;

    // error codes for verifyTx
    uint constant ERR_BAD_FEE = 20010;
    uint constant ERR_CONFIRMATIONS = 20020;
    uint constant ERR_CHAIN = 20030;
    uint constant ERR_MERKLE_ROOT = 20040;
    uint constant ERR_TX_64BYTE = 20050;

    // error codes for relayTx
    uint constant ERR_RELAY_VERIFY = 30010;

    // Not declared constant because they won't be readable from inline assembly
    uint BYTES_1 = 2**8;
    uint BYTES_2 = 2**16;
    uint BYTES_3 = 2**24;
    uint BYTES_4 = 2**32;
    uint BYTES_5 = 2**40;
    uint BYTES_6 = 2**48;
    uint BYTES_7 = 2**56;
    uint BYTES_8 = 2**64;
    uint BYTES_9 = 2**72;
    uint BYTES_10 = 2**80;
    uint BYTES_11 = 2**88;
    uint BYTES_12 = 2**96;
    uint BYTES_13 = 2**104;
    uint BYTES_14 = 2**112;
    uint BYTES_15 = 2**120;
    uint BYTES_16 = 2**128;
    uint BYTES_17 = 2**136;
    uint BYTES_18 = 2**144;
    uint BYTES_19 = 2**152;
    uint BYTES_20 = 2**160;
    uint BYTES_21 = 2**168;
    uint BYTES_22 = 2**176;
    uint BYTES_23 = 2**184;
    uint BYTES_24 = 2**192;
    uint BYTES_25 = 2**200;
    uint BYTES_26 = 2**208;
    uint BYTES_27 = 2**216;
    uint BYTES_28 = 2**224;
    uint BYTES_29 = 2**232;
    uint BYTES_30 = 2**240;
    uint BYTES_31 = 2**248;
    //uint constant BYTES_32 = 2**256;
}

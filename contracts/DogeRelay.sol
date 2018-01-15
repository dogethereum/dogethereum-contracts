pragma solidity ^0.4.19;
//pragma experimental ABIEncoderV2;

import "./TransactionProcessor.sol";

contract DogeRelay {

    enum Network { MAINNET, TESTNET }

    // Number of block ancestors stored in BlockInformation._ancestor
    uint8 constant private NUM_ANCESTOR_DEPTHS = 8;

    // list for internal usage only that allows a 32 byte blockHash to be looked up
    // with a 32bit int
    // This is not designed to be used for anything else, eg it contains all block
    // hashes and nothing can be assumed about which blocks are on the main chain
    mapping (uint32 => uint) private internalBlock;

    // counter for next available slot in internalBlock
    // 0 means no blocks stored yet and is used for the special of storing 1st block
    // which cannot compute Bitcoin difficulty since it doesn't have the 2016th parent
    uint32 private ibIndex;

    // a Bitcoin block (header) is stored as:
    // - _blockHeader 80 bytes + AuxPow (merge mining field)
    // - _info who's 32 bytes are comprised of "_height" 8bytes, "_ibIndex" 8F==bytes, "_score" 16bytes
    // -   "_height" is 1 more than the typical Bitcoin term height/blocknumber [see setInitialParent()]
    // -   "_ibIndex" is the block's index to internalBlock (see btcChain)
    // -   "_score" is 1 more than the chainWork [see setInitialParent()]
    // - _ancestor stores 8 32bit ancestor indices for more efficient backtracking (see btcChain)
    // - _feeInfo is used for incentive.se (see m_getFeeInfo)
    struct BlockInformation {
          bytes _blockHeader;
          uint _info;
          uint _ancestor;
          // bytes _feeInfo;
    }
    //BlockInformation[] myblocks = new BlockInformation[](2**256);
    // block hash => BlockInformation
    mapping (uint => BlockInformation) internal myblocks;

    // hash of the block with the highest score (aka the Tip of the blockchain)
    uint internal bestBlockHash;

    // highest score among all blocks (so far)
    uint private highScore;

    // network the block was mined in
    Network private net;

    // TODO: Make event parameters indexed so we can register filters on them
    event StoreHeader(uint blockHash, uint returnCode);
    event GetHeader(uint blockHash, uint returnCode);
    event VerifyTransaction(uint txHash, uint returnCode);
    event RelayTransaction(uint txHash, uint returnCode);


    function DogeRelay(Network network) public {
        // gasPriceAndChangeRecipientFee in incentive.se
        // TODO incentive management
        // self.gasPriceAndChangeRecipientFee = 50 * 10**9 * BYTES_16 // 50 shannon and left-align
        net = network;
    }

    // setInitialParent can only be called once and allows testing of storing
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
    function setInitialParent(uint blockHash, uint64 height, uint128 chainWork) public returns (bool) {
        // reuse highScore as the flag for whether setInitialParent() has already been called
        if (highScore != 0) {
            return false;
        } else {
            highScore = 1;  // matches the score that is set below in this function
        }

        // TODO: check height > 145000, that is when Digishield was activated. The problem is that is only for production

        bestBlockHash = blockHash;

        // _height cannot be set to -1 because inMainChain() assumes that
        // a block with height 0 does NOT exist (thus we cannot allow the
        // real genesis block to be at height 0)
        m_setHeight(blockHash, height);

        // do NOT pass chainWork of 0, since score 0 means
        // block does NOT exist. see check in storeBlockHeader()
        m_setScore(blockHash, chainWork);

        // other fields do not need to be set, for example:
        // _ancestor can remain zeros because internalBlock[0] already points to blockHash

        return true;
    }



    // Where the header begins:
    // 4 bytes function ID +
    // 32 bytes pointer to header array data +
    // 32 bytes block hash
    // 32 bytes header array size.
    // To understand abi encoding, read https://medium.com/@hayeah/how-to-decipher-a-smart-contract-method-call-8ee980311603
    // Not declared constant because inline assembly would not be able to use it.
    // Declared uint so it has no offset to access it from assebly
    uint OFFSET_ABI = 100;

    // store a Dogecoin block header that must be provided in bytes format 'blockHeaderBytes'
    // Callers must keep same signature since CALLDATALOAD is used to save gas.
    function storeBlockHeader(bytes blockHeaderBytes, uint proposedScryptBlockHash) public returns (uint) {
        // blockHash should be a function parameter in dogecoin because the hash can not be calculated onchain.
        // Code here should call the Scrypt validator contract to make sure the supplied hash of the block is correct
        // If the block is merge mined, there are 2 Scrypts functions to execute, the one that checks PoW of the litecoin block
        // and the one that checks the block hash

        uint blockSha256Hash = m_dblShaFlip(sliceArray(blockHeaderBytes, 0, 80));

        uint hashPrevBlock = f_hashPrevBlock(blockHeaderBytes);

        uint128 scorePrevBlock = m_getScore(hashPrevBlock);
        if (scorePrevBlock == 0) {
            StoreHeader(blockSha256Hash, ERR_NO_PREV_BLOCK);
            return 0;
        }

        if (m_getScore(blockSha256Hash) != 0) {
            // block already stored/exists
            StoreHeader(blockSha256Hash, ERR_BLOCK_ALREADY_EXISTS);
            return 0;
        }

        uint32 bits = f_bits(blockHeaderBytes);
        uint target = targetFromBits(bits);

        // we only check the target and do not do other validation (eg timestamp) to save gas
        // Comment out PoW validation until we implement doge specific code
        //if (blockHash < 0 || blockHash > target) {
        //    StoreHeader (blockHash, ERR_PROOF_OF_WORK);
        //    return 0;
        //}


        uint blockHeight = 1 + m_getHeight(hashPrevBlock);
        uint32 prevBits = m_getBits(hashPrevBlock);

        //log0(bytes32(blockHeight));

        if (blockHeight == 0xb478c) {
            assert(m_getTimestamp(blockSha256Hash) < m_getTimestamp(hashPrevBlock));
        }

        if (!m_difficultyShouldBeAdjusted(blockHeight) || ibIndex == 0) {
            // since blockHeight is 1 more than blockNumber; OR clause is special case for 1st header
            // we need to check prevBits isn't 0 otherwise the 1st header
            // will always be rejected (since prevBits doesn't exist for the initial parent)
            // This allows blocks with arbitrary difficulty from being added to
            // the initial parent, but as these forks will have lower score than
            // the main chain, they will not have impact.
            //log0(bytes32(blockHeight));
            //log1(bytes32(prevBits), bytes32(bits));
            if (bits != prevBits && prevBits != 0) {
                StoreHeader(blockSha256Hash, ERR_DIFFICULTY);
                return 0;
            }
        } else if (ibIndex == 1) {
            // In order to avoid the 'grandparent block bug', we don't check anything
            // for the 2nd stored block now. This should be implemented later!!!

            //log1(bytes32(blockHeight), bytes32(m_getTimestamp(hashPrevBlock)));
            //log1(bytes32(prevBits), bytes32(bits));
        } else {
            // (blockHeight - DIFFICULTY_ADJUSTMENT_INTERVAL) is same as [getHeight(hashPrevBlock) - (DIFFICULTY_ADJUSTMENT_INTERVAL - 1)]

            //log2(bytes32(blockHeight), bytes32(m_getTimestamp(hashPrevBlock)), bytes32(m_getTimestamp(internalBlock[m_getAncestor(hashPrevBlock, 0)])));

            uint32 newBits = m_computeNewBits(m_getTimestamp(hashPrevBlock), m_getTimestamp(internalBlock[m_getAncestor(hashPrevBlock, 0)]),
                                              targetFromBits(prevBits));

            //assert(blockHeight != 793209 || m_getTimestamp(blockSha256Hash) > m_getTimestamp(hashPrevBlock) + 120);
            //if (m_getTimestamp(hashPrevBlock) > m_getTimestamp(internalBlock[m_getAncestor(hashPrevBlock, 0)]) + 120) {
            //if (blockHeight == 0xb4789 && m_getTimestamp(blockSha256Hash) > m_getTimestamp(hashPrevBlock) + 120) {
            if (net == Network.TESTNET && m_getTimestamp(hashPrevBlock) - m_getTimestamp(blockSha256Hash) > 120) {
                log1(bytes32(blockHeight), bytes32("DOGE"));
                newBits = 0x1e0fffff;
            }
            //log3(bytes32(blockHeight), bytes32(prevBits), bytes32(bits), bytes32(newBits));

            // Comment out difficulty adjustment verification until we implement doge algorithm
            if (bits != newBits && newBits != 0) {  // newBits != 0 to allow first header
                StoreHeader(blockSha256Hash, ERR_RETARGET);
                return 0;
            }
        }

        m_saveAncestors(blockSha256Hash, hashPrevBlock);  // increments ibIndex

        myblocks[blockSha256Hash]._blockHeader = sliceArray(blockHeaderBytes, 0, 80);

        // https://en.bitcoin.it/wiki/Difficulty
        // Min difficulty for bitcoin is 0x1d00ffff
        //uint128 scoreBlock = scorePrevBlock + uint128 (0x00000000FFFF0000000000000000000000000000000000000000000000000000 / target);
        // Min difficulty for dogecoin is 0x1e0fffff
        uint128 scoreBlock = scorePrevBlock + uint128 (0x00000FFFFF000000000000000000000000000000000000000000000000000000 / target);
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

        StoreHeader(blockSha256Hash, blockHeight);
        return blockHeight;
    }

    // Implementation of DigiShield, almost directly translated from
    // C++ implementation of Dogecoin. See function CalculateDogecoinNextWorkRequired
    // on dogecoin/src/dogecoin.cpp for more details.
    // Calculates the next block's difficulty based on the current block's elapsed time
    // and the desired mining time for a block, which is 60 seconds after block 145k.
    function calculateDigishieldDifficulty(uint nActualTimespan, uint32 nBits) private returns (uint32 result) {
        // nActualTimespan: time elapsed from previous block creation til current block creation
        // i.e., how much time it took to mine the current block
        // nBits: previous block header difficulty (in bits)
        int64 retargetTimespan = int64(TARGET_TIMESPAN);
        int64 nModulatedTimespan = int64(nActualTimespan);

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

        // This should yield the same result as bnNew.setCompact(pIndexLast->nBits)
        // in the C++ implementation, assuming nBits indeed corresponds
        // to the previous block header's bits. Make sure this is correct.
        uint bnNew = targetFromBits(nBits);
        uint add1;
        bnNew = bnNew * uint(nModulatedTimespan);
        bnNew = uint(bnNew) / uint(retargetTimespan);
        log0(bytes32(bnNew));

        if (bnNew > POW_LIMIT) {
            bnNew = POW_LIMIT;
        }

        log1(bytes32(bnNew), bytes32(m_toCompactBits(bnNew)));

        // Again, this should correspond to bnNew.GetCompact() from the Dogecoin
        // C++ implementation. Double check everything!
        return m_toCompactBits(bnNew);
    }

    // store a number of blockheaders
    // Return latest's block height
    // headersBytes are dogecoin block headers.
    //              Each header is encoded as:
    //              - header size (4 bytes, big-endian representation)
    //              - the header (size is variable).
    // hashesBytes are the scrypt hashes for those blocks
    // count is the number of headers sent
    function bulkStoreHeaders(bytes headersBytes, bytes hashesBytes, uint16 count) public returns (uint result) {
        //uint8 HEADER_SIZE = 80;
        uint8 HASH_SIZE = 32;
        uint32 headersOffset = 0;
        uint32 headersEndIndex = 4;
        uint32 hashesOffset = 0;
        uint32 hashesEndIndex = HASH_SIZE;
        uint16 i = 0;
        while (i < count) {
            bytes memory currHeaderLengthBytes = sliceArray(headersBytes, headersOffset, headersEndIndex);
            uint32 currHeaderLength = bytesToUint32(currHeaderLengthBytes);
            headersOffset += 4;
            headersEndIndex += currHeaderLength;
            //log2(bytes32(currHeaderLength), bytes32(headersOffset), bytes32(headersEndIndex));
            bytes memory currHeader = sliceArray(headersBytes, headersOffset, headersEndIndex);
            bytes memory currHash = sliceArray(hashesBytes, hashesOffset, hashesEndIndex);
            uint currHashUint = uint(bytesToBytes32(currHash));
            //log2(bytes32(currHashUint), bytes32(hashesOffset), bytes32(hashesEndIndex));
            result = storeBlockHeader(currHeader, currHashUint);
            headersOffset += currHeaderLength;
            headersEndIndex += 4;
            hashesOffset += HASH_SIZE;
            hashesEndIndex += HASH_SIZE;
            i += 1;
        }

        // If bytes[] function parameter would work
        //for (uint i = 0; i < headersBytes.length; i++) {
        //      result = storeBlockHeader(headers[i], hashes[i]);
        //}
    }

    // Converts a bytes of size 4 to uint32
    // Eg for input [0x01, 0x02, 0x03 0x04] returns 0x01020304
    function bytesToUint32(bytes memory input) internal pure returns (uint32 result) {
        result = uint32(input[0])*(2**24) + uint32(input[1])*(2**16) + uint32(input[2])*(2**8) + uint32(input[3]);
    }


    // Returns the hash of tx (raw bytes) if the tx is in the block given by 'txBlockHash'
    // and the block is in Bitcoin's main chain (ie not a fork).
    // Returns 0 if the tx is exactly 64 bytes long (to guard against a Merkle tree
    // collision) or fails verification.
    //
    // the merkle proof is represented by 'txIndex', 'siblings', where:
    // - 'txIndex' is the index of the tx within the block
    // - 'siblings' are the merkle siblings of tx
    function verifyTx(bytes txBytes, uint txIndex, uint[] siblings, uint txBlockHash) public returns (uint) {
        uint txHash = m_dblShaFlip(txBytes);
        if (txBytes.length == 64) {  // todo: is check 32 also needed?
            VerifyTransaction(txHash, ERR_TX_64BYTE);
            return 0;
        }
        uint res = helperVerifyHash__(txHash, txIndex, siblings, txBlockHash);
        if (res == 1) {
            return txHash;
        } else {
            // log is done via helperVerifyHash__
            return 0;
        }
    }



    // Returns 1 if txHash is in the block given by 'txBlockHash' and the block is
    // in Bitcoin's main chain (ie not a fork)
    // Note: no verification is performed to prevent txHash from just being an
    // internal hash in the Merkle tree. Thus this helper method should NOT be used
    // directly and is intended to be private.
    //
    // the merkle proof is represented by 'txHash', 'txIndex', 'siblings', where:
    // - 'txHash' is the hash of the tx
    // - 'txIndex' is the index of the tx within the block
    // - 'siblings' are the merkle siblings of tx
    function helperVerifyHash__(uint256 txHash, uint txIndex, uint[] siblings, uint txBlockHash) private returns (uint) {
        // TODO: implement when dealing with incentives
        // if (!feePaid(txBlockHash, m_getFeeAmount(txBlockHash))) {  // in incentive.se
        //    VerifyTransaction(txHash, ERR_BAD_FEE);
        //    return (ERR_BAD_FEE);
        // }

        if (within6Confirms(txBlockHash)) {
            VerifyTransaction(txHash, ERR_CONFIRMATIONS);
            return (ERR_CONFIRMATIONS);
        }

  //      if (!priv_inMainChain__(txBlockHash)) {
  //          VerifyTransaction (txHash, ERR_CHAIN);
  //          return (ERR_CHAIN);
  //      }

        uint merkle = computeMerkle(txHash, txIndex, siblings);
        uint realMerkleRoot = getMerkleRoot(txBlockHash);

        if (merkle != realMerkleRoot) {
          VerifyTransaction (txHash, ERR_MERKLE_ROOT);
          return (ERR_MERKLE_ROOT);
        }

        VerifyTransaction (txHash, 1);
        return (1);
    }



    // relays transaction to target 'contract' processTransaction() method.
    // returns and logs the value of processTransaction(), which is an int256.
    //
    // if the transaction does not pass verification, error code ERR_RELAY_VERIFY
    // is logged and returned.
    // Note: callers cannot be 100% certain when an ERR_RELAY_VERIFY occurs because
    // it may also have been returned by processTransaction(). callers should be
    // aware of the contract that they are relaying transactions to and
    // understand what that contract's processTransaction method returns.
    function relayTx(bytes txBytes, uint txIndex, uint[] siblings, uint txBlockHash, TransactionProcessor targetContract) public returns (uint) {
        uint txHash = verifyTx(txBytes, txIndex, siblings, txBlockHash);
        if (txHash != 0) {
            uint returnCode = targetContract.processTransaction(txBytes, txHash);
            RelayTransaction (txHash, returnCode);
            return (returnCode);
        }

        RelayTransaction (0, ERR_RELAY_VERIFY);
        return(ERR_RELAY_VERIFY);
    }


    // Returns a list of block hashes (9 hashes maximum) that helps an agent find out what
    // doge blocks DogeRelay is missing.
    // The first position contains bestBlock, then bestBlock-5, then bestBlock-25 ... until bestBlock-78125
    function getBlockLocator() public view returns (uint[9] locator) {
        uint blockHash = bestBlockHash;
        //locator.push(blockHash);
        locator[0] = blockHash;
        for (uint8 i = 0 ; i < NUM_ANCESTOR_DEPTHS ; i++) {
            uint blockHash2 = internalBlock[m_getAncestor(blockHash, i)];
            //if (blockHash2 != 0) {
            //    locator.push(blockHash2);
            //}
            locator[i+1] = blockHash2;
        }
        return locator;
    }

    // return the height of the best block aka the Tip
    function getBestBlockHeight() public view returns (uint) {
        return m_getHeight(bestBlockHash);
    }

    // return the hash of the heaviest block aka the Tip
    function getBestBlockHash() public view returns (uint) {
        return bestBlockHash;
    }

    // save the ancestors for a block, as well as updating the height
    // note: this is internal/private
    function m_saveAncestors(uint blockHash, uint hashPrevBlock) private {
        internalBlock[ibIndex] = blockHash;
        m_setIbIndex(blockHash, ibIndex);
        ibIndex += 1;

        m_setHeight(blockHash, m_getHeight(hashPrevBlock) + 1);

        // 8 indexes into internalBlock can be stored inside one ancestor (32 byte) word
        uint ancWord = 0;

        // the first ancestor is the index to hashPrevBlock, and write it to ancWord
        uint32 prevIbIndex = m_getIbIndex(hashPrevBlock);
        ancWord = m_mwrite32(ancWord, 0, prevIbIndex);

        // update ancWord with the remaining indexes
        for (uint8 i = 1 ; i < NUM_ANCESTOR_DEPTHS ; i++) {
            uint depth = m_getAncDepth(i);
            if (m_getHeight(blockHash) % depth == 1) {
                ancWord = m_mwrite32(ancWord, 4*i, prevIbIndex);
            } else {
                ancWord = m_mwrite32(ancWord, 4*i, m_getAncestor(hashPrevBlock, i));
            }
        }
        //log1(bytes32(blockHash), bytes32(ancWord));

        // write the ancestor word to storage
        myblocks[blockHash]._ancestor = ancWord;
    }


    // private (to prevent leeching)
    // returns 1 if 'blockHash' is in the main chain, ie not a fork
    // otherwise returns 0
    function priv_inMainChain__(uint blockHash) private view returns (bool) {
        require(msg.sender == address(this));

        uint blockHeight = m_getHeight(blockHash);

        // By assuming that a block with height 0 does not exist, we can do
        // this optimization and immediate say that blockHash is not in the main chain.
        // However, the consequence is that
        // the genesis block must be at height 1 instead of 0 [see setInitialParent()]
        if (blockHeight == 0) {
          return false;
        }

        return (priv_fastGetBlockHash__(blockHeight) == blockHash);
    }



    // private (to prevent leeching)
    // callers must ensure 2 things:
    // * blockHeight is greater than 0 (otherwise infinite loop since
    // minimum height is 1)
    // * blockHeight is less than the height of bestBlockHash, otherwise the
    // bestBlockHash is returned
    function priv_fastGetBlockHash__(uint blockHeight) internal view returns (uint) {
        //Comment out require to make tests work
        //require(msg.sender == address(this));

        uint blockHash = bestBlockHash;
        uint8 anc_index = NUM_ANCESTOR_DEPTHS - 1;

        while (m_getHeight(blockHash) > blockHeight) {
            while (m_getHeight(blockHash) - blockHeight < m_getAncDepth(anc_index) && anc_index > 0) {
                anc_index -= 1;
            }
            blockHash = internalBlock[m_getAncestor(blockHash, anc_index)];
        }

        return blockHash;
    }



    // a block's _ancestor storage slot contains 8 indexes into internalBlock, so
    // this function returns the index that can be used to lookup the desired ancestor
    // eg. for combined usage, internalBlock[m_getAncestor(someBlock, 2)] will
    // return the block hash of someBlock's 3rd ancestor
    function m_getAncestor(uint blockHash, uint8 whichAncestor) private view returns (uint32) {
        return uint32 ((myblocks[blockHash]._ancestor * (2**(32*uint(whichAncestor)))) / BYTES_28);
    }


    // index should be 0 to 7, so this returns 1, 5, 25 ... 78125
    function m_getAncDepth(uint8 index) private pure returns (uint) {
        return 5**(uint(index));
    }



    // write $int64 to memory at $addrLoc
    // This is useful for writing 64bit ints inside one 32 byte word
    function m_mwrite64(uint word, uint8 position, uint64 eightBytes) private pure returns (uint) {
        // Store uint in a struct wrapper because that is the only way to get a pointer to it
        UintWrapper memory uw = UintWrapper(word);
        uint pointer = ptr(uw);
        assembly {
            mstore8(add(pointer, position        ), byte(24, eightBytes))
            mstore8(add(pointer, add(position, 1)), byte(25, eightBytes))
            mstore8(add(pointer, add(position, 2)), byte(26, eightBytes))
            mstore8(add(pointer, add(position, 3)), byte(27, eightBytes))
            mstore8(add(pointer, add(position, 4)), byte(28, eightBytes))
            mstore8(add(pointer, add(position, 5)), byte(29, eightBytes))
            mstore8(add(pointer, add(position, 6)), byte(30, eightBytes))
            mstore8(add(pointer, add(position, 7)), byte(31, eightBytes))
        }
        return uw.value;
    }



    // write $int128 to memory at $addrLoc
    // This is useful for writing 128bit ints inside one 32 byte word
    function m_mwrite128(uint word, uint8 position, uint128 sixteenBytes) private pure returns (uint) {
        // Store uint in a struct wrapper because that is the only way to get a pointer to it
        UintWrapper memory uw = UintWrapper(word);
        uint pointer = ptr(uw);
        assembly {
            mstore8(add(pointer, position         ),  byte(16, sixteenBytes))
            mstore8(add(pointer, add(position,  1)),  byte(17, sixteenBytes))
            mstore8(add(pointer, add(position,  2)),  byte(18, sixteenBytes))
            mstore8(add(pointer, add(position,  3)),  byte(19, sixteenBytes))
            mstore8(add(pointer, add(position,  4)),  byte(20, sixteenBytes))
            mstore8(add(pointer, add(position,  5)),  byte(21, sixteenBytes))
            mstore8(add(pointer, add(position,  6)),  byte(22, sixteenBytes))
            mstore8(add(pointer, add(position,  7)),  byte(23, sixteenBytes))
            mstore8(add(pointer, add(position,  8)),  byte(24, sixteenBytes))
            mstore8(add(pointer, add(position,  9)),  byte(25, sixteenBytes))
            mstore8(add(pointer, add(position,  10)), byte(26, sixteenBytes))
            mstore8(add(pointer, add(position,  11)), byte(27, sixteenBytes))
            mstore8(add(pointer, add(position,  12)), byte(28, sixteenBytes))
            mstore8(add(pointer, add(position,  13)), byte(29, sixteenBytes))
            mstore8(add(pointer, add(position,  14)), byte(30, sixteenBytes))
            mstore8(add(pointer, add(position,  15)), byte(31, sixteenBytes))
        }
        return uw.value;
    }

    // writes fourBytes into word at position
    // This is useful for writing 32bit ints inside one 32 byte word
    function m_mwrite32(uint word, uint8 position, uint32 fourBytes) private pure returns (uint) {
        // Store uint in a struct wrapper because that is the only way to get a pointer to it
        UintWrapper memory uw = UintWrapper(word);
        uint pointer = ptr(uw);
        assembly {
            mstore8(add(pointer, position), byte(28, fourBytes))
            mstore8(add(pointer, add(position,1)), byte(29, fourBytes))
            mstore8(add(pointer, add(position,2)), byte(30, fourBytes))
            mstore8(add(pointer, add(position,3)), byte(31, fourBytes))
        }
        return uw.value;
    }

    // writes threeBytes into word at position
    // This is useful for writing 24bit ints inside one 32 byte word
    function m_mwrite24(uint word, uint8 position, uint24 threeBytes) private pure returns (uint) {
        // Store uint in a struct wrapper because that is the only way to get a pointer to it
        UintWrapper memory uw = UintWrapper(word);
        uint pointer = ptr(uw);
        assembly {
            mstore8(add(pointer, position), byte(29, threeBytes))
            mstore8(add(pointer, add(position,1)), byte(30, threeBytes))
            mstore8(add(pointer, add(position,2)), byte(31, threeBytes))
        }
        return uw.value;
    }

    // writes twoBytes into word at position
    // This is useful for writing 16bit ints inside one 32 byte word
    function m_mwrite16(uint word, uint8 position, uint16 twoBytes) private pure returns (uint) {
        // Store uint in a struct wrapper because that is the only way to get a pointer to it
        UintWrapper memory uw = UintWrapper(word);
        uint pointer = ptr(uw);
        assembly {
            mstore8(add(pointer, position), byte(30, twoBytes))
            mstore8(add(pointer, add(position,1)), byte(31, twoBytes))
        }
        return uw.value;
    }


    // Should be private, made internal for testing
    function bytesToBytes32(bytes b) internal pure returns (bytes32) {
        bytes32 out;
        for (uint i = 0; i < 32; i++) {
            out |= bytes32(b[i] & 0xFF) >> (i * 8);
        }
        return out;
    }


    // Should be private, made internal for testing
    function sliceArray(bytes memory original, uint32 offset, uint32 endIndex) internal view returns (bytes) {
        uint len = endIndex - offset;
        bytes memory result = new bytes(len);
        assembly {
            // Call precompiled contract to copy data
            if iszero(call(not(0), 0x04, 0, add(add(original, 0x20), offset), len, add(result, 0x20), len)) {
                revert(0, 0)
            }
        }
        return result;
    }

    // For a valid proof, returns the root of the Merkle tree.
    // Otherwise the return value is meaningless if the proof is invalid.
    // [see documentation for verifyTx() for the merkle proof
    // format of 'txHash', 'txIndex', 'siblings' ]
    function computeMerkle(uint txHash, uint txIndex, uint[] siblings) private pure returns (uint) {
        uint resultHash = txHash;
        uint proofLen = siblings.length;
        uint i = 0;
        while (i < proofLen) {
            uint proofHex = siblings[i];

            uint sideOfSiblings = txIndex % 2;  // 0 means siblings is on the right; 1 means left

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

            txIndex /= 2;
            i += 1;
        }

        return resultHash;
    }


    // returns 1 if the 'txBlockHash' is within 6 blocks of self.bestBlockHash
    // otherwise returns 0.
    // note: return value of 0 does NOT mean 'txBlockHash' has more than 6
    // confirmations; a non-existent 'txBlockHash' will lead to a return value of 0
    function within6Confirms(uint txBlockHash) private view returns (bool) {
        uint blockHash = bestBlockHash;
        uint8 i = 0;
        while (i < 6) {
            if (txBlockHash == blockHash) {
                return true;
            }
            // blockHash = self.block[blockHash]._prevBlock
            blockHash = getPrevBlock(blockHash);
            i += 1;
        }
        return false;
    }

    function m_difficultyShouldBeAdjusted(uint blockHeight) private pure returns (bool) {
        return ((blockHeight % DIFFICULTY_ADJUSTMENT_INTERVAL) == 0);
    }

    function m_computeNewBits(uint prevTime, uint startTime, uint prevTarget) private returns (uint32) {
        uint actualTimespan = prevTime - startTime;
//        if (actualTimespan < TARGET_TIMESPAN_DIV_4) {
//            actualTimespan = TARGET_TIMESPAN_DIV_4;
//        }
//        if (actualTimespan > TARGET_TIMESPAN_MUL_4) {
//            actualTimespan = TARGET_TIMESPAN_MUL_4;
//        }
//        uint newTarget = actualTimespan * prevTarget / TARGET_TIMESPAN;
//        if (newTarget > UNROUNDED_MAX_TARGET) {
//            newTarget = UNROUNDED_MAX_TARGET;
//        }
        uint32 bits = m_toCompactBits(prevTarget);
        return calculateDigishieldDifficulty(actualTimespan, bits);
    }



    // Convert uint256 to compact encoding
    // based on https://github.com/petertodd/python-bitcoinlib/blob/2a5dda45b557515fb12a0a18e5dd48d2f5cd13c2/bitcoin/core/serialize.py
    // Analogous to arith_uint256::GetCompact from C++ implementation
    function m_toCompactBits(uint val) private pure returns (uint32) {
        uint8 nbytes = uint8 (m_shiftRight((m_bitLen(val) + 7), 3));
        uint32 compact = 0;
        if (nbytes <= 3) {
            compact = uint32 (m_shiftLeft((val & 0xFFFFFF), 8 * (3 - nbytes)));
        } else {
            compact = uint32 (m_shiftRight(val, 8 * (nbytes - 3)));
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


    // Analogous to arith_uint256::SetCompact from C++ implementation
    function m_setCompact(uint32 nCompact, bool pfNegative, bool pfOverflow) {}


    // get the parent blok hash of 'blockHash'
    function getPrevBlock(uint blockHash) internal view returns (uint) {
        // sload($addr) gets first 32bytes
        // * BYTES_4 shifts over to skip the 4bytes of blockversion
        // At this point we have the first 28bytes of hashPrevBlock and we
        // want to get the remaining 4bytes so we:
        // sload($addr+1) get the second 32bytes
        //     but we only want the first 4bytes so div 28bytes
        // The single line statement can be interpreted as:
        // get the last 28bytes of the 1st chunk and combine (add) it to the
        // first 4bytes of the 2nd chunk,
        // where chunks are read in sizes of 32bytes via sload

        uint pointer = ptr(myblocks[blockHash]._blockHeader);
        uint chunk1;
        uint chunk2;
        assembly {
            chunk1 := sload(pointer)
            chunk2 := sload(add(pointer,1))
        }
        return flip32Bytes(chunk1 * BYTES_4 + chunk2/BYTES_28);
    }


    // get the timestamp from a Bitcoin blockheader
    function m_getTimestamp(uint blockHash) internal view returns (uint32 result) {
        uint pointer = ptr(myblocks[blockHash]._blockHeader);
        assembly {
            // get the 3rd chunk
            let tmp := sload(add(pointer,2))
            // the timestamp are the 4th to 7th bytes of the 3rd chunk, but we also have to flip them
            result := add( mul(sload(BYTES_3_slot),byte(7, tmp)) , add( mul(sload(BYTES_2_slot),byte(6, tmp)) , add( mul(sload(BYTES_1_slot),byte(5, tmp)) , byte(4, tmp) ) ) )
        }
     }

    // get the 'bits' field from a Bitcoin blockheader
    function m_getBits(uint blockHash) internal view returns (uint32 result) {
        uint pointer = ptr(myblocks[blockHash]._blockHeader);
        assembly {
            // get the 3rd chunk
            let tmp := sload(add(pointer,2))
            // the 'bits' are the 8th to 11th bytes of the 3rd chunk, but we also have to flip them
            result := add( mul(sload(BYTES_3_slot),byte(11, tmp)) , add( mul(sload(BYTES_2_slot),byte(10, tmp)) , add( mul(sload(BYTES_1_slot),byte(9, tmp)) , byte(8, tmp) ) ) )
        }
    }

    // get the merkle root of '$blockHash'
    function getMerkleRoot(uint blockHash) private view returns (uint) {
        uint pointer = ptr(myblocks[blockHash]._blockHeader);
        uint chunk2;
        uint chunk3;
        assembly {
            chunk2 := sload(add(pointer,1))
            chunk3 := sload(add(pointer,2))
        }
        return flip32Bytes(chunk2 * BYTES_4 + chunk3/BYTES_28);
    }


    // Bitcoin-way of hashing
    function m_dblShaFlip(bytes dataBytes) private pure returns (uint) {
        return flip32Bytes(uint(sha256(sha256(dataBytes))));
    }



    // Bitcoin-way of computing the target from the 'bits' field of a blockheader
    // based on http://www.righto.com/2014/02/bitcoin-mining-hard-way-algorithms.html//ref3
    function targetFromBits(uint32 bits) internal pure returns (uint) {
        uint exp = bits / 0x1000000;  // 2**24
        uint mant = bits & 0xffffff;
        return mant * 256**(exp - 3);
        //return mant;
    }


    // Bitcoin-way merkle parent of transaction hashes $tx1 and $tx2
    function concatHash(uint tx1, uint tx2) internal pure returns (uint) {
        bytes memory concat = new bytes(64);
        uint tx1Flipped = flip32Bytes(tx1);
        uint tx2Flipped = flip32Bytes(tx2);
        assembly {
          // First 32 bytes are the byte array size
          mstore(add(concat, 32), tx1Flipped)
          mstore(add(concat, 64), tx2Flipped)
        }
        return flip32Bytes(uint(sha256(sha256(concat))));
    }


    function m_shiftRight(uint val, uint8 shift) private pure returns (uint) {
        return val / uint(2)**shift;
    }

    function m_shiftLeft(uint val, uint8 shift) private pure returns (uint) {
        return val * uint(2)**shift;
    }

    // bit length of '$val'
    function m_bitLen(uint val) private pure returns (uint8 length) {
        uint int_type = val;
        while (int_type > 0) {
          int_type = m_shiftRight(int_type, 1);
          length += 1;
        }
    }

    // reverse 32 bytes given by '$b32'
    function flip32Bytes(uint input) internal pure returns (uint) {
        uint8 i = 0;
        // unrolling this would decrease gas usage, but would increase
        // the gas cost for code size by over 700K and exceed the PI million block gas limit
        UintWrapper memory uw = UintWrapper(0);
        uint pointer = ptr(uw);
        while (i < 32) {
            assembly {
                mstore8(add(pointer, i), byte(sub(31 ,i), input))
            }
            i++;
        }
        return uw.value;
    }




    //
    //  function accessors for a block's _info (height, ibIndex, score)
    //

    // block height is the first 8 bytes of _info
    function m_setHeight(uint blockHash, uint64 blockHeight) private {
        uint info = myblocks[blockHash]._info;
        info = m_mwrite64(info, 0, blockHeight);
        myblocks[blockHash]._info = info;
    }

    function m_getHeight(uint blockHash) internal view returns (uint64) {
        return uint64(myblocks[blockHash]._info / BYTES_24);
    }


    // ibIndex is the index to self.internalBlock: it's the second 8 bytes of _info
    function m_setIbIndex(uint blockHash, uint32 internalIndex) private {
        uint info = myblocks[blockHash]._info;
        uint64 internalIndex64 = internalIndex;
        info = m_mwrite64(info, 8, internalIndex64);
        myblocks[blockHash]._info = info;
     }

    function m_getIbIndex(uint blockHash) private view returns (uint32) {
        return uint32(myblocks[blockHash]._info * BYTES_8 / BYTES_24);
    }


    // score of the block is the last 16 bytes of _info
    function m_setScore(uint blockHash, uint128 blockScore) private {
        uint info = myblocks[blockHash]._info;
        info = m_mwrite128(info, 16, blockScore);
        myblocks[blockHash]._info = info;
    }

    function m_getScore(uint blockHash) internal view returns (uint128) {
        return uint128(myblocks[blockHash]._info * BYTES_16 / BYTES_16);
    }

    // Util functions and wrappers to get pointers to memory and storage
    struct UintWrapper {
        uint value;
    }
    // Returns a pointer to the supplied UintWrapper
    function ptr(UintWrapper memory uw) private pure returns (uint addr) {
        assembly {
            addr := uw
        }
    }
    // Returns a pointer to the supplied BlockInformation
    function ptr(BlockInformation storage bi) private pure returns (uint addr) {
        assembly {
            addr := bi_slot
        }
    }
    // Returns a pointer to the content of the supplied byte array in storage
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

    function f_hashPrevBlock(bytes memory blockHeader) internal pure returns (uint) {
        uint hashPrevBlock;
        assembly {
            hashPrevBlock := mload(add(blockHeader, 0x24))
        }
        return flip32Bytes(hashPrevBlock);
    }

    function f_bits(bytes memory blockHeader) internal pure returns (uint32 bits) {
        assembly {
            let word := mload(add(blockHeader, 0x50))
            bits := add(byte(24, word),
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
    uint256 constant POW_LIMIT = 0x00000fffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    //
    // Error / failure codes
    //

    // error codes for storeBlockHeader
    uint constant ERR_DIFFICULTY =  10010;  // difficulty didn't match current difficulty
    uint constant ERR_RETARGET = 10020;  // difficulty didn't match retarget
    uint constant ERR_NO_PREV_BLOCK = 10030;
    uint constant ERR_BLOCK_ALREADY_EXISTS = 10040;
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

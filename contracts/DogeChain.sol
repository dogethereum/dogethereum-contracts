pragma solidity ^0.4.4;

import "./Constants.sol";

// contract DogeChain is extended by DogeRelay and is a separate file to improve
// clarity: it has ancestor management and its
// main method is inMainChain() which is tested by test_btcChain
contract DogeChain is Constants {
	uint8 constant NUM_ANCESTOR_DEPTHS = 8; 

	// list for internal usage only that allows a 32 byte blockHash to be looked up
	// with a 32bit int
	// This is not designed to be used for anything else, eg it contains all block
	// hashes and nothing can be assumed about which blocks are on the main chain
	bytes32[] internalBlock = new bytes32[](2**50);

	// counter for next available slot in internalBlock
	// 0 means no blocks stored yet and is used for the special of storing 1st block
	// which cannot compute Bitcoin difficulty since it doesn't have the 2016th parent
	uint32 ibIndex;


	// save the ancestors for a block, as well as updating the height
	// note: this is internal/private
	function saveAncestors(bytes32 blockHash, bytes32 hashPrevBlock) {
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


    // write the ancestor word to storage
    myblocks[blockHash]._ancestor = ancWord;
  }


	// private (to prevent leeching)
	// returns 1 if 'txBlockHash' is in the main chain, ie not a fork
	// otherwise returns 0
	function priv_inMainChain__(bytes32 txBlockHash) private returns (bool) {
	    require(msg.sender == address(this));

	    uint txBlockHeight = m_getHeight(txBlockHash);

	    // By assuming that a block with height 0 does not exist, we can do
	    // this optimization and immediate say that txBlockHash is not in the main chain.
	    // However, the consequence is that
	    // the genesis block must be at height 1 instead of 0 [see setInitialParent()]
	    if (txBlockHeight == 0) {
	        return false;	    
	    }

	    return priv_fastGetBlockHash__(txBlockHeight) == txBlockHash;
	}



	// private (to prevent leeching)
	// callers must ensure 2 things:
	// * blockHeight is greater than 0 (otherwise infinite loop since
	// minimum height is 1)
	// * blockHeight is less than the height of heaviestBlock, otherwise the
	// heaviestBlock is returned
	function priv_fastGetBlockHash__(uint blockHeight) private returns (bytes32) {
	    require(msg.sender == address(this));

	    bytes32 blockHash = heaviestBlock;
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
	function m_getAncestor(bytes32 blockHash, uint8 whichAncestor) returns (uint32) {
  	return uint32 ((myblocks[blockHash]._ancestor * (2**(32*uint(whichAncestor)))) / BYTES_28);
	}


	// index should be 0 to 7, so this returns 1, 5, 25 ... 78125
	function m_getAncDepth(uint8 index) returns (uint) {
	    return 5**(uint(index));
	}



	// write int32 to memory at addrLoc
	// This is useful for writing 32bit ints inside one 32 byte word
	function m_mwrite32(uint word, uint8 position, uint32 fourBytes) public constant returns (uint) {
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


  struct UintWrapper {
      uint value;
  }
    

  function ptr(UintWrapper memory uw) internal pure returns (uint addr) {
        assembly {
            addr := uw
        }
    }  

  // mock

  struct BlockInformation {
        uint _ancestor;
  }
  //BlockInformation[] myblocks = new BlockInformation[](2**256);
	mapping (bytes32 => BlockInformation) myblocks;

	function m_setIbIndex(bytes32 blockHash, uint32 internalIndex) {revert;}
	function m_getHeight(bytes32 blockHash) returns (uint) { revert; }
	bytes32 heaviestBlock;
	function m_setHeight(bytes32 blockHash, uint height) {revert;}
	function m_getIbIndex(bytes32 blockHash) returns (uint32) {revert;}
	function m_mwrite32(uint target, uint position, uint32 source) returns (uint) {revert;}


}


/*

----


	// write $int24 to memory at $addrLoc
	// This is useful for writing 24bit ints inside one 32 byte word
	macro m_mwrite24($addrLoc, $int24):
	    with $addr = $addrLoc:
	        with $threeBytes = $int24:
	            mstore8($addr, byte(29, $threeBytes))
	            mstore8($addr + 1, byte(30, $threeBytes))
	            mstore8($addr + 2, byte(31, $threeBytes))


	// write $int16 to memory at $addrLoc
	// This is useful for writing 16bit ints inside one 32 byte word
	macro m_mwrite16($addrLoc, $int16):
	    with $addr = $addrLoc:
	        with $twoBytes = $int16:
	            mstore8($addr, byte(30, $twoBytes))
	            mstore8($addr + 1, byte(31, $twoBytes))




//
// macros
//


*/             

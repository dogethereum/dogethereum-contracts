pragma solidity ^0.4.15;

contract Constants {


 // Constants
 
 // for verifying Bitcoin difficulty
 uint constant DIFFICULTY_ADJUSTMENT_INTERVAL = 2016;  // Bitcoin adjusts every 2 weeks
 uint constant TARGET_TIMESPAN = 14 * 24 * 60 * 60;  // 2 weeks
 uint constant TARGET_TIMESPAN_DIV_4 = TARGET_TIMESPAN / 4;
 uint constant TARGET_TIMESPAN_MUL_4 = TARGET_TIMESPAN * 4;
 uint constant UNROUNDED_MAX_TARGET = 2**224 - 1;  // different from (2**16-1)*2**208 http =//bitcoin.stackexchange.com/questions/13803/how/ exactly-was-the-original-coefficient-for-difficulty-determined
 
 //
 // Error / failure codes
 //
 
 // error codes for storeBlockHeader
 uint constant ERR_DIFFICULTY =  10010;  // difficulty didn't match current difficulty
 uint constant ERR_RETARGET = 10020;  // difficulty didn't match retarget
 uint constant ERR_NO_PREV_BLOCK = 10030;
 uint constant ERR_BLOCK_ALREADY_EXISTS = 10040;
 uint constant ERR_PROOF_OF_WORK = 10090;
 uint constant ERR_BLOCK_HASH_DOES_NOT_MATCHES_CALCULATED_ONE = 10100;
 
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



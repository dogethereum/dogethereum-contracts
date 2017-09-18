pragma solidity ^0.4.4;

library Constants {


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
 
 // error codes for verifyTx
 uint constant ERR_BAD_FEE = 20010;
 uint constant ERR_CONFIRMATIONS = 20020;
 uint constant ERR_CHAIN = 20030;
 uint constant ERR_MERKLE_ROOT = 20040;
 uint constant ERR_TX_64BYTE = 20050;
 
 // error codes for relayTx
 uint constant ERR_RELAY_VERIFY = 30010;
 
 
 uint constant BYTES_1 = 2**8;
 uint constant BYTES_2 = 2**16;
 uint constant BYTES_3 = 2**24;
 uint constant BYTES_4 = 2**32;
 uint constant BYTES_5 = 2**40;
 uint constant BYTES_6 = 2**48;
 uint constant BYTES_7 = 2**56;
 uint constant BYTES_8 = 2**64;
 uint constant BYTES_9 = 2**72;
 uint constant BYTES_10 = 2**80;
 uint constant BYTES_11 = 2**88;
 uint constant BYTES_12 = 2**96;
 uint constant BYTES_13 = 2**104;
 uint constant BYTES_14 = 2**112;
 uint constant BYTES_15 = 2**120;
 uint constant BYTES_16 = 2**128;
 uint constant BYTES_17 = 2**136;
 uint constant BYTES_18 = 2**144;
 uint constant BYTES_19 = 2**152;
 uint constant BYTES_20 = 2**160;
 uint constant BYTES_21 = 2**168;
 uint constant BYTES_22 = 2**176;
 uint constant BYTES_23 = 2**184;
 uint constant BYTES_24 = 2**192;
 uint constant BYTES_25 = 2**200;
 uint constant BYTES_26 = 2**208;
 uint constant BYTES_27 = 2**216;
 uint constant BYTES_28 = 2**224;
 uint constant BYTES_29 = 2**232;
 uint constant BYTES_30 = 2**240;
 uint constant BYTES_31 = 2**248;
 //uint constant BYTES_32 = 2**256;

}



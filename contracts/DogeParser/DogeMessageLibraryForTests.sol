// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

import {DogeMessageLibrary} from "./DogeMessageLibrary.sol";

// @dev - Manages a battle session between superblock submitter and challenger
contract DogeMessageLibraryForTests {
  function bytesToUint32Public(bytes memory input) public pure returns (uint32 result) {
    return bytesToUint32(input, 0);
  }

  function bytesToBytes32Public(bytes calldata b) public pure returns (bytes32) {
    return bytesToBytes32(b, 0);
  }

  function sliceArrayPublic(
    bytes calldata original,
    uint32 offset,
    uint32 endIndex
  ) public view returns (bytes memory result) {
    return DogeMessageLibrary.sliceArray(original, offset, endIndex);
  }

  function targetFromBitsPublic(uint32 bits) public pure returns (uint256) {
    return DogeMessageLibrary.targetFromBits(bits);
  }

  function concatHashPublic(uint256 tx1, uint256 tx2) public pure returns (uint256) {
    return DogeMessageLibrary.concatHash(tx1, tx2);
  }

  function flip32BytesPublic(uint256 input) public pure returns (uint256) {
    return DogeMessageLibrary.flip32Bytes(input);
  }

  function checkAuxPoWPublic(uint256 blockHash, bytes calldata auxBytes)
    public
    view
    returns (uint256)
  {
    return checkAuxPoWForTests(blockHash, auxBytes);
  }

  // doesn't check merge mining to see if other error codes work
  function checkAuxPoWForTests(uint256 blockHash, bytes memory auxBytes)
    internal
    view
    returns (uint256)
  {
    DogeMessageLibrary.AuxPoW memory auxPow = DogeMessageLibrary.parseAuxPoW(
      auxBytes,
      0,
      auxBytes.length
    );

    //uint32 version = bytesToUint32Flipped(auxBytes, 0);

    if (!DogeMessageLibrary.isMergeMined(auxBytes, 0)) {
      return ERR_NOT_MERGE_MINED;
    }

    if (auxPow.coinbaseTxIndex != 0) {
      return ERR_COINBASE_INDEX;
    }

    if (auxPow.coinbaseMerkleRootCode != 1) {
      return auxPow.coinbaseMerkleRootCode;
    }

    if (DogeMessageLibrary.computeChainMerkle(blockHash, auxPow) != auxPow.coinbaseMerkleRoot) {
      return ERR_CHAIN_MERKLE;
    }

    if (DogeMessageLibrary.computeParentMerkle(auxPow) != auxPow.parentMerkleRoot) {
      return ERR_PARENT_MERKLE;
    }

    return 1;
  }

  // @dev - Converts a bytes of size 4 to uint32,
  // e.g. for input [0x01, 0x02, 0x03 0x04] returns 0x01020304
  function bytesToUint32(bytes memory input, uint256 pos) internal pure returns (uint32 result) {
    result =
      uint32(uint8(input[pos])) *
      (2**24) +
      uint32(uint8(input[pos + 1])) *
      (2**16) +
      uint32(uint8(input[pos + 2])) *
      (2**8) +
      uint32(uint8(input[pos + 3]));
  }

  // @dev converts bytes of any length to bytes32.
  // If `rawBytes` is longer than 32 bytes, it truncates to the 32 leftmost bytes.
  // If it is shorter, it pads with 0s on the left.
  // Should be private, made internal for testing
  //
  // @param rawBytes - arbitrary length bytes
  // @return - leftmost 32 or less bytes of input value; padded if less than 32
  function bytesToBytes32(bytes memory rawBytes, uint256 pos) internal pure returns (bytes32) {
    bytes32 out;
    assembly {
      out := mload(add(add(rawBytes, 0x20), pos))
    }
    return out;
  }

  function parseLockTransaction(bytes calldata txBytes, bytes20 expectedOutputPublicKeyHash)
    public
    pure
    returns (
      uint256,
      address,
      uint32
    )
  {
    return DogeMessageLibrary.parseLockTransaction(txBytes, expectedOutputPublicKeyHash);
  }

  function parseUnlockTransaction(
    bytes calldata txBytes,
    uint256 amountOfInputs,
    uint256 amountOfOutputs
  )
    public
    pure
    returns (
      DogeMessageLibrary.Outpoint[] memory outpoints,
      DogeMessageLibrary.P2PKHOutput[] memory outputs
    )
  {
    return DogeMessageLibrary.parseUnlockTransaction(txBytes, amountOfInputs, amountOfOutputs);
  }

  //
  // Error / failure codes
  //

  // error codes for storeBlockHeader
  uint256 constant ERR_COINBASE_INDEX = 10060; // coinbase tx index within Litecoin merkle isn't 0
  uint256 constant ERR_NOT_MERGE_MINED = 10070; // trying to check AuxPoW on a block that wasn't merge mined
  uint256 constant ERR_CHAIN_MERKLE = 10110;
  uint256 constant ERR_PARENT_MERKLE = 10120;
}

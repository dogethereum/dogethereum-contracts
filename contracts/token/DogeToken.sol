pragma solidity ^0.4.8;

import "./HumanStandardToken.sol";
import "./Set.sol";
import "./../TransactionProcessor.sol";
import "../DogeParser/DogeTx.sol";

contract DogeToken is HumanStandardToken(0, "DogeToken", 8, "DOGETOKEN"), TransactionProcessor {

    address private _trustedDogeRelay;

    Set.Data dogeTxHashesAlreadyProcessed;
    uint256 minimumLockTxValue;

    function DogeToken(address trustedDogeRelay) public {
        _trustedDogeRelay = trustedDogeRelay;
        minimumLockTxValue = 100000000;
    }

    function processTransaction(bytes dogeTx, uint256 txHash) public returns (uint) {
        log0("processTransaction called");

        uint out1;
        bytes20 addr1;
        uint out2;
        bytes20 addr2;
        (out1, addr1, out2, addr2) = DogeTx.getFirstTwoOutputs(dogeTx);

        //FIXME: Use address from first input
        address destinationAddress = address(addr1);

        // Check tx was not processes already and add it to the dogeTxHashesAlreadyProcessed
        require(Set.insert(dogeTxHashesAlreadyProcessed, txHash));

        //FIXME: Modify test so we can uncomment this
        //only allow trustedDogeRelay, otherwise anyone can provide a fake dogeTx
        //require(msg.sender == _trustedDogeRelay);

        balances[destinationAddress] += out1;

        log1("processTransaction txHash, ", bytes32(txHash));
        return 1;
    }

    uint constant p = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f;  // secp256k1
    uint constant q = (p + 1) / 4;

    function getAddress(bytes pubKey) view internal returns (address) {
        uint x;
        bool odd;
        require(pubKey.length == 33);
        require(pubKey[0] == 2 || pubKey[0] == 3);
        odd = pubKey[0] == 3;
        assembly {
            x := mload(add(pubKey, 33))
        }
        //FIXME: Check Legendre operator to ensure x is valid
        return pub2address(x, odd);
    }

    function expmod(uint256 base, uint256 e, uint256 m) internal constant returns (uint256 o) {
        // are all of these inside the precompile now?

        assembly {
            // define pointer
            let p := mload(0x40)
            // store data assembly-favouring ways
            mstore(p, 0x20)             // Length of Base
            mstore(add(p, 0x20), 0x20)  // Length of Exponent
            mstore(add(p, 0x40), 0x20)  // Length of Modulus
            mstore(add(p, 0x60), base)  // Base
            mstore(add(p, 0x80), e)     // Exponent
            mstore(add(p, 0xa0), m)     // Modulus
            // call modexp precompile!
            if iszero(call(not(0), 0x05, 0, p, 0xc0, p, 0x20)) {
                revert(0, 0)
            }
            // data
            o := mload(p)
        }
    }

    function pub2address(uint x, bool odd) internal returns (address) {
        uint yy = mulmod(x, x, p);
        yy = mulmod(yy, x, p);
        yy = addmod(yy, 7, p);
        uint y = expmod(yy, q, p);
        if (((y & 1) == 1) != odd) {
          y = p - y;
        }
        return address(keccak256(x, y));
    }

    struct DogeTransaction {
    }

    struct DogePartialMerkleTree {
    }


    function registerDogeTransaction(DogeTransaction dogeTx, DogePartialMerkleTree pmt, uint blockHeight) private {
        // Validate tx is valid and has enough confirmations, then assigns tokens to sender of the doge tx
    }

    function releaseDoge(uint256 _value) public {
        balances[msg.sender] -= _value;
        // Send the tokens back to the doge blockchain.
    }
}

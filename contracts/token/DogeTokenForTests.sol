pragma solidity ^0.4.19;

import "./DogeToken.sol";

contract DogeTokenForTests is DogeToken {

    function DogeTokenForTests(address trustedDogeRelay, address trustedDogeEthPriceOracle, bytes20 recipientDogethereum) public DogeToken(trustedDogeRelay, trustedDogeEthPriceOracle, recipientDogethereum) {

    }

    function assign(address _to, uint256 _value) public {
        balances[_to] += _value;
    }

    function addUtxo(uint value, uint txHash, uint16 outputIndex) public {
        utxos.push(Utxo(value, txHash, outputIndex));
    }
}

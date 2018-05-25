pragma solidity ^0.4.19;

import "./DogeToken.sol";

contract DogeTokenForTests is DogeToken {

    function DogeTokenForTests(address _trustedDogeRelay, address _trustedDogeEthPriceOracle, uint8 _collateralRatio) public DogeToken(_trustedDogeRelay, _trustedDogeEthPriceOracle, _collateralRatio) {

    }

    function assign(address _to, uint256 _value) public {
        balances[_to] += _value;
    }

    function addOperatorSimple(bytes20 operatorPublicKeyHash) public {
        Operator operator = operators[operatorPublicKeyHash];
        operator.ethAddress = msg.sender;
    }

    function addUtxo(bytes20 operatorPublicKeyHash, uint value, uint txHash, uint16 outputIndex) public {
        Operator operator = operators[operatorPublicKeyHash];
        operator.utxos.push(Utxo(value, txHash, outputIndex));
        operator.dogeAvailableBalance += value;
    }

    // Similar to DogeToken.addOperator() but makes no checks before adding the operator
    function addOperator2(bytes20 operatorPublicKeyHash) public {
        Operator storage operator = operators[operatorPublicKeyHash];
        operator.ethAddress = msg.sender;
    }    
}

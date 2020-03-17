pragma solidity 0.5.16;

import "./DogeToken.sol";

contract DogeTokenForTests is DogeToken {

    constructor (address _trustedRelayerContract, address _trustedDogeEthPriceOracle, uint8 _collateralRatio) public DogeToken(_trustedRelayerContract, _trustedDogeEthPriceOracle, _collateralRatio) {

    }

    function assign(address _to, uint256 _value) public {
        balances[_to] += _value;
    }

    // Similar to DogeToken.addOperator() but makes no checks before adding the operator
    function addOperatorSimple(bytes20 operatorPublicKeyHash, address operatorEthAddress) public {
        Operator storage operator = operators[operatorPublicKeyHash];
        operator.ethAddress = operatorEthAddress;
    }

    function addUtxo(bytes20 operatorPublicKeyHash, uint value, uint txHash, uint16 outputIndex) public {
        Operator storage operator = operators[operatorPublicKeyHash];
        operator.utxos.push(Utxo(value, txHash, outputIndex));
        operator.dogeAvailableBalance += value;
    }

    function addDogeAvailableBalance(bytes20 operatorPublicKeyHash, uint value) public {
        Operator storage operator = operators[operatorPublicKeyHash];
        operator.dogeAvailableBalance += value;
    }

    function subtractDogeAvailableBalance(bytes20 operatorPublicKeyHash, uint value) public {
        Operator storage operator = operators[operatorPublicKeyHash];
        operator.dogeAvailableBalance -= value;
    }

}

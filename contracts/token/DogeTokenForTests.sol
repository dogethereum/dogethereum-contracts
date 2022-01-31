// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./DogeToken.sol";

contract DogeTokenForTests is DogeToken {
    using SafeMath for uint256;

    function assign(address to, uint256 value) public {
        balances[to] = balances[to].add(value);
        totalSupply = totalSupply.add(value);
    }

    // Similar to DogeToken.addOperator() but makes no checks before adding the operator
    function addOperatorSimple(bytes20 operatorPublicKeyHash, address operatorEthAddress) public {
        Operator storage operator = operators[operatorPublicKeyHash];
        operator.ethAddress = operatorEthAddress;
        operatorKeys.push(OperatorKey(operatorPublicKeyHash, false));
    }

    function addUtxo(
        bytes20 operatorPublicKeyHash,
        uint256 value,
        uint256 txHash,
        uint16 outputIndex
    ) public {
        Operator storage operator = operators[operatorPublicKeyHash];
        operator.utxos.push(Utxo(value, txHash, outputIndex));
        operator.dogeAvailableBalance += value;
    }

    function addDogeAvailableBalance(bytes20 operatorPublicKeyHash, uint256 value) public {
        Operator storage operator = operators[operatorPublicKeyHash];
        operator.dogeAvailableBalance += value;
    }

    function subtractDogeAvailableBalance(bytes20 operatorPublicKeyHash, uint256 value) public {
        Operator storage operator = operators[operatorPublicKeyHash];
        operator.dogeAvailableBalance -= value;
    }
}

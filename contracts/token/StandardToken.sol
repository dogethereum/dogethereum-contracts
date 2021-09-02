// SPDX-License-Identifier: GPL-3.0-only    

/*
You should inherit from StandardToken or, for a token like you would want to
deploy in something like Mist, see HumanStandardToken.sol.
(This implements ONLY the standard functions and NOTHING else.
If you deploy this, you won't have anything useful.)

Implements ERC 20 Token standard: https://github.com/ethereum/EIPs/issues/20
.*/
pragma solidity ^0.7.6;

import "./Token.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract StandardToken is Token {

    using SafeMath for uint;

    function transfer(address to, uint256 value) override public returns (bool success) {
        //Default assumes totalSupply can't be over max (2^256 - 1).
        //If your token leaves out totalSupply and can issue more tokens as time goes on, you need to check if it doesn't wrap.
        //Replace the if with this one instead.
        //require(balances[msg.sender] >= value && balances[to] + value > balances[to]);
        require(balances[msg.sender] >= value);
        balances[msg.sender] = balances[msg.sender].sub(value);
        balances[to] = balances[to].add(value);
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) override public returns (bool success) {
        //same as above. Replace this line with the following if you want to protect against wrapping uints.
        //require(balances[from] >= value && allowed[from][msg.sender] >= value && balances[to] + value > balances[to]);
        require(balances[from] >= value && allowed[from][msg.sender] >= value);
        balances[to] = balances[to].add(value);
        balances[from] = balances[from].sub(value);
        allowed[from][msg.sender] = allowed[from][msg.sender].sub(value);
        emit Transfer(from, to, value);
        return true;
    }

    function balanceOf(address owner) override public view returns (uint256 balance) {
        return balances[owner];
    }

    function approve(address spender, uint256 value) override public returns (bool success) {
        allowed[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function allowance(address owner, address spender) override public view returns (uint256 remaining) {
        return allowed[owner][spender];
    }

    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;
}

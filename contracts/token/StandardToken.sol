// SPDX-License-Identifier: GPL-3.0-only    

// Implements ERC 20 Token standard: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

contract StandardToken {
    using SafeMath for uint;

    // Total amount of tokens
    // This generates a getter function that conforms to the ERC20 standard.
    uint256 public totalSupply;
    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @notice Send `value` tokens to `to` from `msg.sender`
     * @param to The address of the recipient
     * @param value The amount of token to be transferred
     * @return success Whether the transfer was successful or not
     */
    function transfer(address to, uint256 value) public returns (bool success) {
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

    /**
     * @notice Send `value` tokens to `to` from `from` on the condition it is approved by `from`
     * @param from The address of the sender
     * @param to The address of the recipient
     * @param value The amount of token to be transferred
     * @return success Whether the transfer was successful or not
     */
    function transferFrom(address from, address to, uint256 value) public returns (bool success) {
        //same as above. Replace this line with the following if you want to protect against wrapping uints.
        //require(balances[from] >= value && allowed[from][msg.sender] >= value && balances[to] + value > balances[to]);
        require(balances[from] >= value && allowed[from][msg.sender] >= value);
        balances[to] = balances[to].add(value);
        balances[from] = balances[from].sub(value);
        allowed[from][msg.sender] = allowed[from][msg.sender].sub(value);
        emit Transfer(from, to, value);
        return true;
    }

    /**
     * @param owner The address from which the balance will be retrieved
     * @return balance The balance
     */
    function balanceOf(address owner) public view returns (uint256 balance) {
        return balances[owner];
    }

    /**
     * @notice `msg.sender` approves `spender` to spend `value` tokens
     * @param spender The address of the account able to transfer the tokens
     * @param value The amount of tokens to be approved for transfer
     * @return success Whether the approval was successful or not
     */
    function approve(address spender, uint256 value) public returns (bool success) {
        allowed[msg.sender][spender] = value;

        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @param owner The address of the account owning tokens
     * @param spender The address of the account able to transfer the tokens
     * @return remaining Amount of tokens allowed to spend
     */
    function allowance(address owner, address spender) public view returns (uint256 remaining) {
        return allowed[owner][spender];
    }
}

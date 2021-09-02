// SPDX-License-Identifier: GPL-3.0-only    

// Abstract contract for the full ERC 20 Token standard
// https://github.com/ethereum/EIPs/issues/20
pragma solidity ^0.7.6;

abstract contract Token {
    /* This is a slight change to the ERC20 base standard.
    function totalSupply() view returns (uint256 supply);
    is replaced with:
    uint256 public totalSupply;
    This automatically creates a getter function for the totalSupply.
    This is moved to the base contract since public getter functions are not
    currently recognised as an implementation of the matching abstract
    function by the compiler.
    */
    /// total amount of tokens
    uint256 public totalSupply;

    /// @param owner The address from which the balance will be retrieved
    /// @return balance The balance
    function balanceOf(address owner) virtual public view returns (uint256 balance);

    /// @notice send `value` token to `to` from `msg.sender`
    /// @param to The address of the recipient
    /// @param value The amount of token to be transferred
    /// @return success Whether the transfer was successful or not
    function transfer(address to, uint256 value) virtual public returns (bool success);

    /// @notice send `value` token to `to` from `from` on the condition it is approved by `from`
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param value The amount of token to be transferred
    /// @return success Whether the transfer was successful or not
    function transferFrom(address from, address to, uint256 value) virtual public returns (bool success);

    /// @notice `msg.sender` approves `spender` to spend `value` tokens
    /// @param spender The address of the account able to transfer the tokens
    /// @param value The amount of tokens to be approved for transfer
    /// @return success Whether the approval was successful or not
    function approve(address spender, uint256 value) virtual public returns (bool success);

    /// @param owner The address of the account owning tokens
    /// @param spender The address of the account able to transfer the tokens
    /// @return remaining Amount of remaining tokens allowed to spent
    function allowance(address owner, address spender) virtual public view returns (uint256 remaining);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

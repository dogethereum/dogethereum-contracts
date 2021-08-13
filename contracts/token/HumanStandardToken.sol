// SPDX-License-Identifier: GPL-3.0-only

/*
This Token Contract implements the standard token functionality (https://github.com/ethereum/EIPs/issues/20) as well as the following OPTIONAL extras intended for use by humans.

In other words. This is intended for deployment in something like a Token Factory or Mist wallet, and then used by humans.
Imagine coins, currencies, shares, voting weight, etc.
Machine-based, rapid creation of many tokens would not necessarily need these extra features or will be minted in other manners.

1) Initial Finite Supply (upon creation one specifies how much is minted).
2) In the absence of a token registry: Optional Decimal, Symbol & Name.
3) Optional approveAndCall() functionality to notify a contract if an approval() has occurred.

.*/

import "./StandardToken.sol";

pragma solidity ^0.7.6;

contract HumanStandardToken is StandardToken {

    /* Public variables of the token */

    /*
    NOTE:
    The following variables are OPTIONAL vanities. One does not have to include them.
    They allow one to customise the token contract & in no way influences the core functionality.
    Some wallets/interfaces might not even bother to look at this information.
    */

    // Name for display purposes
    string public constant name = "DogeToken";
    // Decimals for display purposes
    // How many decimals to show. ie. There could 1000 base units with 3 decimals.
    // Meaning 0.980 SBX = 980 base units. It's like comparing 1 wei to 1 ether.
    uint8 public constant decimals = 8;
    // An identifier: eg SBX
    string public constant symbol = "DOGETOKEN";

    /* Approves and then calls the receiving contract */
    function approveAndCall(address _spender, uint256 _value, bytes calldata _extraData) public returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);

        //call the receiveApproval function on the contract you want to be notified. This crafts the function signature manually so one doesn't have to include a contract in here just for this.
        //receiveApproval(address _from, uint256 _value, address _tokenContract, bytes _extraData)
        //it is assumed that when does this that the call *should* succeed, otherwise one would use vanilla approve instead.
        (bool success2,) = _spender.call(abi.encodeWithSignature("receiveApproval(address,uint256,address,bytes)", msg.sender, _value, this, _extraData));
        require(success2);
        return true;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

contract DepositsManager {
    using SafeMath for uint256;

    mapping(address => uint256) public deposits;

    event DepositMade(address who, uint256 amount);
    event DepositWithdrawn(address who, uint256 amount);

    // @dev – fallback to calling makeDeposit when ether is sent directly to contract.
    receive() external payable {
        makeDeposit();
    }

    // @dev – returns an account's deposit
    // @param who – the account's address.
    // @return – the account's deposit.
    function getDeposit(address who) public view returns (uint256) {
        return deposits[who];
    }

    // @dev – allows a user to deposit eth.
    // @return – the user's updated deposit amount.
    function makeDeposit() public payable returns (uint256) {
        increaseDeposit(msg.sender, msg.value);
        return deposits[msg.sender];
    }

    // @dev – increases an account's deposit.
    // @return – the user's updated deposit amount.
    function increaseDeposit(address who, uint256 amount) internal {
        deposits[who] += amount;
        require(deposits[who] <= address(this).balance);

        emit DepositMade(who, amount);
    }

    // @dev – allows a user to withdraw eth from their deposit.
    // @param amount – how much eth to withdraw
    // @return – the user's updated deposit amount.
    function withdrawDeposit(uint256 amount) public returns (uint256) {
        require(deposits[msg.sender] >= amount);

        deposits[msg.sender] -= amount;
        msg.sender.transfer(amount);

        emit DepositWithdrawn(msg.sender, amount);
        return deposits[msg.sender];
    }
}

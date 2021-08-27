// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol";

contract AggregatorMock is AggregatorV3Interface {
    address owner;
    uint256 price;
    bool dataPresent;

    constructor(uint256 initPrice) {
        price = initPrice;
        dataPresent = true;
        owner = msg.sender;
    }

    function setPrice(uint256 newPrice) external {
        require(msg.sender == owner, "Only the owner can set the price.");
        price = newPrice;
    }

    function setDataPresent(bool newPresentFlag) external {
        require(msg.sender == owner, "Only the owner can set the present flag.");
        dataPresent = newPresentFlag;
    }

    function decimals() override external pure returns (uint8) {
        return 8;
    }

    function description() override external pure returns (string memory) {
        return "Oracle mock";
    }

    function version() override external pure returns (uint256) {
        return 1337;
    }

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(
        uint80 reqRoundId
    ) override external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        require(dataPresent, "Oracle does not have enough data");
        return (reqRoundId, int256(price), 0, 0, 0);
    }

    function latestRoundData() override external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        require(dataPresent, "Oracle does not have enough data");
        return (0, int256(price), 0, 0, 0);
    }
}

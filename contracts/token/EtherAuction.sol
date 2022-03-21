// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

abstract contract EtherAuction {
  using SafeMath for uint256;

  // Minimum duration in terms of seconds.
  uint256 public constant auctionMinimumDuration = 2 hours;

  enum AuctionStatus {
    Uninitialized,
    Open,
    Closed
  }

  struct Auction {
    uint256 bestBid;
    address payable bestBidder;
    AuctionStatus status;
    uint256 endTimestamp;
  }

  function auctionIsInexistent(Auction storage auction) internal view returns (bool) {
    return auction.status == AuctionStatus.Uninitialized;
  }

  function auctionIsOpen(Auction storage auction) internal view returns (bool) {
    return auction.status == AuctionStatus.Open;
  }

  function auctionIsClosed(Auction storage auction) internal view returns (bool) {
    return auction.status == AuctionStatus.Closed;
  }

  function auctionOpen(Auction storage auction) internal returns (uint256) {
    require(auctionIsInexistent(auction), "The auction must be uninitialized.");
    auction.status = AuctionStatus.Open;
    uint256 endTimestamp = block.timestamp.add(auctionMinimumDuration);
    auction.endTimestamp = endTimestamp;
    return endTimestamp;
  }

  /**
   * Registers bid from bidder in auction.
   * We allow outbidding against oneself.
   */
  function auctionBid(
    Auction storage auction,
    address payable bidder,
    uint256 tokenAmount
  ) internal {
    require(auctionIsOpen(auction), "The auction must be open.");
    require(auction.bestBid < tokenAmount, "The bid must be higher than the best bid.");

    address lastBidder = auction.bestBidder;
    uint256 lastBid = auction.bestBid;
    if (lastBidder != address(0)) {
      releaseTokens(lastBidder, lastBid);
    }

    auction.bestBid = tokenAmount;
    auction.bestBidder = bidder;
    takeTokens(bidder, tokenAmount);
  }

  function auctionClose(Auction storage auction) internal returns (address payable, uint256) {
    require(auctionIsOpen(auction), "The auction must be open.");
    require(auction.bestBidder != address(0), "The auction can't be closed without a bid.");
    require(
      auction.endTimestamp < block.timestamp,
      "The auction can't close before the minimum time window is expired."
    );

    auction.status = AuctionStatus.Closed;
    return (auction.bestBidder, auction.bestBid);
  }

  /**
   * Ensures the tokens are taken and held only for the auction.
   */
  function takeTokens(address bidder, uint256 tokenAmount) internal virtual;

  /**
   * Releases previously held tokens.
   */
  function releaseTokens(address bidder, uint256 tokenAmount) internal virtual;
}

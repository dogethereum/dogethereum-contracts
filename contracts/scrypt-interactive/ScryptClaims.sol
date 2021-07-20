// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import {DepositsManager} from './DepositsManager.sol';
import {ScryptVerifier} from "./ScryptVerifier.sol";
import {IScryptCheckerListener} from "./IScryptCheckerListener.sol";
import {IScryptChecker} from "./IScryptChecker.sol";

import '@openzeppelin/contracts/math/SafeMath.sol';

// ScryptClaims: queues a sequence of challengers to play with a claimant.

contract ScryptClaims is DepositsManager, IScryptChecker {
  using SafeMath for uint;

  uint private numClaims = 1;     // index as key for the claims mapping.
  uint public minDeposit = 1;    // TODO: what should the minimum deposit be?

  // default initial amount of blocks for challenge timeout
  uint public defaultChallengeTimeout = 5;

  ScryptVerifier public scryptVerifier;

  event DepositBonded(uint claimId, address account, uint amount);
  event DepositUnbonded(uint claimId, address account, uint amount);
  event ClaimCreated(uint claimId, address claimant, bytes plaintext, bytes blockHash);
  event ClaimChallenged(uint claimId, address challenger);
  event SessionDecided(uint sessionId, address winner, address loser);
  event ClaimSuccessful(uint claimId, address claimant, bytes plaintext, bytes blockHash);
  event ClaimFailed(uint claimId, address claimant, bytes plaintext, bytes blockHash);
  event VerificationGameStarted(uint claimId, address claimant, address challenger, uint sessionId);//Rename to SessionStarted?
  event ClaimVerificationGamesEnded(uint claimId);

  struct ScryptClaim {
    address claimant;
    bytes plaintext;    // the plaintext Dogecoin block header.
    bytes blockHash;    // the Dogecoin blockhash.
    uint createdAt;     // the block number at which the claim was created.
    address[] challengers;      // all current challengers.
    mapping(address => uint) sessions; //map challengers to sessionId's
    uint numChallengers; // is number of challengers always same as challengers.length ?
    uint currentChallenger;    // index of next challenger to play a verification game.
    bool verificationOngoing;   // is the claim waiting for results from an ongoing verificationg game.
    mapping (address => uint) bondedDeposits;   // all deposits bonded in this claim.
    bool decided;
    bool invalid;
    uint challengeTimeoutBlockNumber;
    bytes32 proposalId;
    IScryptCheckerListener scryptCheckerListener;
  }

//  mapping(address => uint) public claimantClaims;
  mapping(uint => ScryptClaim) private claims;

  modifier onlyScryptVerifier() {
    require(msg.sender == address(scryptVerifier), "This function is restricted to the scrypt verifier contract.");
    _;
  }

  // @dev – the constructor
  constructor(ScryptVerifier _scryptVerifier) {
    scryptVerifier = _scryptVerifier;
  }

  // @dev – locks up part of the user's deposit into a claim.
  // @param claimId – the claim id.
  // @param account – the user's address.
  // @param amount – the amount of deposit to lock up.
  // @return – the user's deposit bonded for the claim.
  function bondDeposit(uint claimId, address account, uint amount) private returns (uint) {
    ScryptClaim storage claim = getValidClaim(claimId);

    require(deposits[account] >= amount, "Not enough balance is available. Deposit more ether.");
    deposits[account] -= amount;

    claim.bondedDeposits[account] = claim.bondedDeposits[account].add(amount);
    emit DepositBonded(claimId, account, amount);
    return claim.bondedDeposits[account];
  }

  // @dev – accessor for a claims bonded deposits.
  // @param claimId – the claim id.
  // @param account – the user's address.
  // @return – the user's deposit bonded for the claim.
  function getBondedDeposit(uint claimId, address account) public view returns (uint) {
    ScryptClaim storage claim = getValidClaim(claimId);

    return claim.bondedDeposits[account];
  }

  // @dev – unlocks a user's bonded deposits from a claim.
  // @param claimId – the claim id.
  // @param account – the user's address.
  // @return – the user's deposit which was unbonded from the claim.
  function unbondDeposit(uint claimId, address account) public returns (uint) {
    ScryptClaim storage claim = getValidClaim(claimId);

    require(claim.decided == true, "The claim is not decided yet.");
    uint bondedDeposit = claim.bondedDeposits[account];
    delete claim.bondedDeposits[account];
    deposits[account] = deposits[account].add(bondedDeposit);
    emit DepositUnbonded(claimId, account, bondedDeposit);

    return bondedDeposit;
  }

  // TODO: Is the first parameter necessary?
  function calcId(bytes memory, bytes32 _hash, address claimant, bytes32 _proposalId) public pure returns (uint) {
    return uint(keccak256(abi.encodePacked(claimant, _hash, _proposalId)));
  }

  // @dev – check whether a DogeCoin blockHash was calculated correctly from the plaintext block header.
  // only callable by the DogeRelay contract.
  // @param _plaintext – the plaintext blockHeader.
  // @param _blockHash – the blockHash.
  // @param claimant – the address of the Dogecoin block submitter.
  function checkScrypt(bytes memory _data, bytes32 _hash, bytes32 _proposalId, IScryptCheckerListener _scryptCheckerListener) external override payable {
    // dogeRelay can directly make a deposit on behalf of the claimant.

    address _submitter = msg.sender;
    if (msg.value != 0) {
      // only call if eth is included (to save gas)
      increaseDeposit(_submitter, msg.value);
    }

    require(deposits[_submitter] >= minDeposit, "The deposit of the submitter should exceed the minimum deposit.");

//    uint claimId = numClaims;
//    uint claimId = uint(keccak256(_submitter, _plaintext, _hash, numClaims));

    uint claimId = uint(keccak256(abi.encodePacked(_submitter, _hash, _proposalId)));

    ScryptClaim storage claim = claims[claimId];
    require(!claimExists(claim), "The claim already exists.");

    claim.claimant = _submitter;
    claim.plaintext = _data;
    claim.blockHash = abi.encode(_hash);
    claim.numChallengers = 0;
    claim.currentChallenger = 0;
    claim.verificationOngoing = false;
    claim.createdAt = block.number;
    claim.decided = false;
    claim.invalid = false;
    claim.proposalId = _proposalId;
    claim.scryptCheckerListener = _scryptCheckerListener;

    bondDeposit(claimId, claim.claimant, minDeposit);
    emit ClaimCreated(claimId, claim.claimant, claim.plaintext, claim.blockHash);

    claim.scryptCheckerListener.scryptSubmitted(claim.proposalId, _hash, _data, msg.sender);
  }

  // @dev – challenge an existing Scrypt claim.
  // triggers a downstream claim computation on the scryptVerifier contract
  // where the claimant & the challenger will immediately begin playing a verification.
  //
  // @param claimId – the claim ID.
  function challengeClaim(uint claimId) public {
    ScryptClaim storage claim = getValidClaim(claimId);

    require(!claim.decided, "The claim is already decided.");
    require(claim.sessions[msg.sender] == 0, "The sender is already challenging this claim.");

    require(deposits[msg.sender] >= minDeposit, "The challenger deposit should exceed the minimum deposit.");
    bondDeposit(claimId, msg.sender, minDeposit);

    claim.challengeTimeoutBlockNumber = block.number.add(defaultChallengeTimeout);
    claim.challengers.push(msg.sender);
    claim.numChallengers = claim.numChallengers.add(1);
    emit ClaimChallenged(claimId, msg.sender);
  }

  // @dev – runs a verification game between the claimant and
  // the next queued-up challenger.
  // @param claimId – the claim id.
  function runNextVerificationGame(uint claimId) public {
    ScryptClaim storage claim = getValidClaim(claimId);

    require(!claim.decided, "The claim is already decided.");

    require(!claim.verificationOngoing, "The claim has an ongoing verification.");

    // check if there is a challenger who has not the played verification game yet.
    if (claim.numChallengers > claim.currentChallenger) {

      // kick off a verification game.
      uint sessionId = scryptVerifier.claimComputation(claimId, claim.challengers[claim.currentChallenger], claim.claimant, claim.plaintext, claim.blockHash, 2050);
      claim.sessions[claim.challengers[claim.currentChallenger]] = sessionId;
      emit VerificationGameStarted(claimId, claim.claimant, claim.challengers[claim.currentChallenger], sessionId);

      claim.verificationOngoing = true;
      claim.currentChallenger = claim.currentChallenger.add(1);
    }
  }

  // @dev – called when a verification game has ended.
  // only callable by the scryptVerifier contract.
  //
  // @param sessionId – the sessionId.
  // @param winner – winner of the verification game.
  // @param loser – loser of the verification game.
  function sessionDecided(uint sessionId, uint claimId, address winner, address loser) onlyScryptVerifier public {
    ScryptClaim storage claim = getValidClaim(claimId);

    require(claim.verificationOngoing, "The claim has no verification ongoing.");
    claim.verificationOngoing = false;

    // reward the winner, with the loser's bonded deposit.
    uint depositToTransfer = claim.bondedDeposits[loser];
    claim.bondedDeposits[winner] = claim.bondedDeposits[winner].add(depositToTransfer);
    delete claim.bondedDeposits[loser];

    if (claim.claimant == loser) {
      // the claim is over.
      // note: no callback needed to the DogeRelay contract,
      // because it by default does not save blocks.

      //Trigger end of verification game
      claim.currentChallenger = claim.numChallengers;
      claim.invalid = true;
    } else if (claim.claimant == winner) {
      // The claim continues in good standing.
      runNextVerificationGame(claimId);
    } else {
      // This can only happen if the scrypt verifier contract decides a session
      // with the claimant being neither the winner nor the loser.
      revert("Invalid session decision.");
    }

    emit SessionDecided(sessionId, winner, loser);
  }

  // @dev – check whether a claim has successfully withstood all challenges.
  // if successful, it will trigger a callback to the DogeRelay contract,
  // notifying it that the Scrypt blockhash was correctly calculated.
  //
  // @param claimId – the claim ID.
  // @todo There are a couple of problems here:
  //       First, the challenger never gets his deposits released.
  //       Second, this function can be called multiple times, so releasing the deposit here seems like a bad idea.
  //       We could make this function callable only once if successful though.
  function checkClaimSuccessful(uint claimId) public {
    ScryptClaim storage claim = getValidClaim(claimId);

    // check that there is no ongoing verification game.
    require(!claim.verificationOngoing, "The claim has an ongoing verification.");

    // TODO: do we really want two separate timeouts? A default value should be just a default.
    // check that the claim has exceeded the default challenge timeout.
    require(
      block.number.sub(claim.createdAt) > defaultChallengeTimeout,
      "The claim has not exceeded the default challenge timeout."
    );

    // check that the claim has exceeded the claim's specific challenge timeout.
    require(block.number > claim.challengeTimeoutBlockNumber, "The claim has not exceeded the challenge timeout");

    // check that all verification games have been played.
    require(claim.numChallengers == claim.currentChallenger, "Some verification games are pending.");

    claim.decided = true;

    if (!claim.invalid) {
      claim.scryptCheckerListener.scryptVerified(claim.proposalId);

      unbondDeposit(claimId, claim.claimant);

      emit ClaimSuccessful(claimId, claim.claimant, claim.plaintext, claim.blockHash);
    } else {
      claim.scryptCheckerListener.scryptFailed(claim.proposalId);

      emit ClaimFailed(claimId, claim.claimant, claim.plaintext, claim.blockHash);
    }
  }

  function claimExists(ScryptClaim storage claim) view private returns(bool) {
    return claim.claimant != address(0);
  }

  function firstChallenger(uint claimId) public view returns(address) {
    ScryptClaim storage claim = getValidClaim(claimId);
    return claim.challengers[0];
  }

  function createdAt(uint claimId) public view returns(uint) {
    ScryptClaim storage claim = getValidClaim(claimId);
    return claim.createdAt;
  }

  function getSession(uint claimId, address challenger) public view returns(uint) {
    ScryptClaim storage claim = getValidClaim(claimId);
    return claim.sessions[challenger];
  }

  function getChallengers(uint claimId) public view returns(address[] memory) {
    ScryptClaim storage claim = getValidClaim(claimId);
    return claim.challengers;
  }

  function getCurrentChallenger(uint claimId) public view returns(address) {
    ScryptClaim storage claim = getValidClaim(claimId);
    return claim.challengers[claim.currentChallenger];
  }

  function getVerificationOngoing(uint claimId) public view returns(bool) {
    ScryptClaim storage claim = getValidClaim(claimId);
    return claim.verificationOngoing;
  }

  function getClaim(uint claimId)
    public
    view
    returns(address claimant, bytes memory plaintext, bytes memory blockHash, bytes32 proposalId)
  {
    ScryptClaim storage claim = claims[claimId];

    return (
      claim.claimant,
      claim.plaintext,
      claim.blockHash,
      claim.proposalId
    );
  }

  /**
   * This function allows the caller to know if a claim is ready to be closed out.
   *
   * @dev This function avoids reverting to allow easy query outside of the contract.
   */
  function getClaimReady(uint claimId) public view returns(bool) {
    ScryptClaim storage claim = claims[claimId];

    // check that the claim exists
    bool exists = claimExists(claim);

    // check that the claim has exceeded the default challenge timeout.
    bool pastChallengeTimeout = block.number.sub(claim.createdAt) > defaultChallengeTimeout;

    // check that the claim has exceeded the claim's specific challenge timeout.
    bool pastClaimTimeout = block.number > claim.challengeTimeoutBlockNumber;

    // check that there is no ongoing verification game.
    bool noOngoingGames = !claim.verificationOngoing;

    // check that all verification games have been played.
    bool noPendingGames = claim.numChallengers == claim.currentChallenger;

    return exists && pastChallengeTimeout && pastClaimTimeout && noOngoingGames && noPendingGames;
  }

  function getClaimStatus(uint claimId) public view returns(bool decided, bool invalid) {
    decided = claims[claimId].decided;
    invalid = claims[claimId].invalid;
  }

  function getValidClaim(uint claimId) private view returns (ScryptClaim storage claim) {
    claim = claims[claimId];
    require(claimExists(claim), "The claim doesn't exist.");
    return claim;
  }
}

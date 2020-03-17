pragma solidity 0.5.16;

import {DepositsManager} from './DepositsManager.sol';
import {ScryptVerifier} from "./ScryptVerifier.sol";
import {IScryptCheckerListener} from "../IScryptCheckerListener.sol";
import {IScryptChecker} from "../IScryptChecker.sol";


// ClaimManager: queues a sequence of challengers to play with a claimant.

contract ClaimManager is DepositsManager, IScryptChecker {
  uint private numClaims = 1;     // index as key for the claims mapping.
  uint public minDeposit = 1;    // TODO: what should the minimum deposit be?

  // default initial amount of blocks for challenge timeout
  uint public defaultChallengeTimeout = 5;

  ScryptVerifier public scryptVerifier;

  event DepositBonded(uint claimID, address account, uint amount);
  event DepositUnbonded(uint claimID, address account, uint amount);
  event ClaimCreated(uint claimID, address claimant, bytes plaintext, bytes blockHash);
  event ClaimChallenged(uint claimID, address challenger);
  event SessionDecided(uint sessionId, address winner, address loser);
  event ClaimSuccessful(uint claimID, address claimant, bytes plaintext, bytes blockHash);
  event ClaimFailed(uint claimID, address claimant, bytes plaintext, bytes blockHash);
  event VerificationGameStarted(uint claimID, address claimant, address challenger, uint sessionId);//Rename to SessionStarted?
  event ClaimVerificationGamesEnded(uint claimID);

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
    IScryptCheckerListener scryptDependent;
  }

//  mapping(address => uint) public claimantClaims;
  mapping(uint => ScryptClaim) private claims;

  modifier onlyBy(address _account) {
    require(msg.sender == _account);
    _;
  }

    // @dev – the constructor
    constructor(ScryptVerifier _scryptVerifier) public {
        scryptVerifier = _scryptVerifier;
    }

  // @dev – locks up part of the a user's deposit into a claim.
  // @param claimID – the claim id.
  // @param account – the user's address.
  // @param amount – the amount of deposit to lock up.
  // @return – the user's deposit bonded for the claim.
  function bondDeposit(uint claimID, address account, uint amount) private returns (uint) {
    ScryptClaim storage claim = claims[claimID];

    require(claimExists(claim));
    require(deposits[account] >= amount);
    deposits[account] -= amount;

    claim.bondedDeposits[account] = claim.bondedDeposits[account].add(amount);
    emit DepositBonded(claimID, account, amount);
    return claim.bondedDeposits[account];
  }

  // @dev – accessor for a claims bonded deposits.
  // @param claimID – the claim id.
  // @param account – the user's address.
  // @return – the user's deposit bonded for the claim.
  function getBondedDeposit(uint claimID, address account) public view returns (uint) {
    ScryptClaim storage claim = claims[claimID];
    require(claimExists(claim));
    return claim.bondedDeposits[account];
  }

  // @dev – unlocks a user's bonded deposits from a claim.
  // @param claimID – the claim id.
  // @param account – the user's address.
  // @return – the user's deposit which was unbonded from the claim.
  function unbondDeposit(uint claimID, address account) public returns (uint) {
    ScryptClaim storage claim = claims[claimID];
    require(claimExists(claim));
    require(claim.decided == true);
    uint bondedDeposit = claim.bondedDeposits[account];
    delete claim.bondedDeposits[account];
    deposits[account] = deposits[account].add(bondedDeposit);
    emit DepositUnbonded(claimID, account, bondedDeposit);

    return bondedDeposit;
  }

  function calcId(bytes memory, bytes32 _hash, address claimant, bytes32 _proposalId) public pure returns (uint) {
    return uint(keccak256(abi.encodePacked(claimant, _hash, _proposalId)));
  }

  // @dev – check whether a Dogecoin block hash was calculated correctly from the plaintext block header.
  // only callable by the DogeRelay contract.
  // @param _plaintext – the plaintext blockHeader.
  // @param _hash – Doge block hash.
  // @param claimant – the address of the Dogecoin block submitter.
  function checkScrypt(bytes calldata _data, bytes32 _hash, bytes32 _proposalId, IScryptCheckerListener _scryptDependent) external payable {
    // dogeRelay can directly make a deposit on behalf of the claimant.

    bytes memory _blockHash = new bytes(32);
    assembly {
      mstore(add(_blockHash, 0x20), _hash)
    }

    address _submitter = tx.origin;
    if (msg.value != 0) {
      // only call if eth is included (to save gas)
      increaseDeposit(_submitter, msg.value);
    }

    require(deposits[_submitter] >= minDeposit);

//    uint claimId = numClaims;
//    uint claimId = uint(keccak256(_submitter, _plaintext, _hash, numClaims));

    uint claimId = uint(keccak256(abi.encodePacked(_submitter, _hash, _proposalId)));
    require(!claimExists(claims[claimId]));

    ScryptClaim storage claim = claims[claimId];
    claim.claimant = _submitter;
    claim.plaintext = _data;
    claim.blockHash = _blockHash;
    claim.numChallengers = 0;
    claim.currentChallenger = 0;
    claim.verificationOngoing = false;
    claim.createdAt = block.number;
    claim.decided = false;
    claim.invalid = false;
    claim.proposalId = _proposalId;
    claim.scryptDependent = _scryptDependent;

    bondDeposit(claimId, claim.claimant, minDeposit);
    emit ClaimCreated(claimId, claim.claimant, claim.plaintext, claim.blockHash);

    claim.scryptDependent.scryptSubmitted(claim.proposalId, _hash, _data, msg.sender);
  }

  // @dev – challenge an existing Scrypt claim.
  // triggers a downstream claim computation on the scryptVerifier contract
  // where the claimant & the challenger will immediately begin playing a verification.
  //
  // @param claimID – the claim ID.
  function challengeClaim(uint claimID) public {
    ScryptClaim storage claim = claims[claimID];

    require(claimExists(claim));
    require(!claim.decided);
    require(claim.sessions[msg.sender] == 0);

    require(deposits[msg.sender] >= minDeposit);
    bondDeposit(claimID, msg.sender, minDeposit);

    claim.challengeTimeoutBlockNumber = block.number.add(defaultChallengeTimeout);
    claim.challengers.push(msg.sender);
    claim.numChallengers = claim.numChallengers.add(1);
    emit ClaimChallenged(claimID, msg.sender);
  }

  // @dev – runs a verification game between the claimant and
  // the next queued-up challenger.
  // @param claimID – the claim id.
  function runNextVerificationGame(uint claimID) public {
    ScryptClaim storage claim = claims[claimID];

    require(claimExists(claim));
    require(!claim.decided);

    require(claim.verificationOngoing == false);

    // check if there is a challenger who has not the played verification game yet.
    if (claim.numChallengers > claim.currentChallenger) {

      // kick off a verification game.
      uint sessionId = scryptVerifier.claimComputation(claimID, claim.challengers[claim.currentChallenger], claim.claimant, claim.plaintext, claim.blockHash, 2049);
      claim.sessions[claim.challengers[claim.currentChallenger]] = sessionId;
      emit VerificationGameStarted(claimID, claim.claimant, claim.challengers[claim.currentChallenger], sessionId);

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
  function sessionDecided(uint sessionId, uint claimID, address winner, address loser) onlyBy(address(scryptVerifier)) public {
    ScryptClaim storage claim = claims[claimID];

    require(claimExists(claim));

    //require(claim.verificationOngoing == true);
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
      // the claim continues.
      runNextVerificationGame(claimID);
    } else {
      revert();
    }

    emit SessionDecided(sessionId, winner, loser);
  }

  // @dev – check whether a claim has successfully withstood all challenges.
  // if successful, it will trigger a callback to the DogeRelay contract,
  // notifying it that the Scrypt blockhash was correctly calculated.
  //
  // @param claimID – the claim ID.
  function checkClaimSuccessful(uint claimID) public {
    ScryptClaim storage claim = claims[claimID];

    require(claimExists(claim));

    // check that there is no ongoing verification game.
    require(claim.verificationOngoing == false);

    // check that the claim has exceeded the default challenge timeout.
    require(block.number.sub(claim.createdAt) > defaultChallengeTimeout);

    //check that the claim has exceeded the claim's specific challenge timeout.
    require(block.number > claim.challengeTimeoutBlockNumber);

    // check that all verification games have been played.
    require(claim.numChallengers == claim.currentChallenger);

    claim.decided = true;

    if (!claim.invalid) {
        claim.scryptDependent.scryptVerified(claim.proposalId);

        unbondDeposit(claimID, claim.claimant);

        emit ClaimSuccessful(claimID, claim.claimant, claim.plaintext, claim.blockHash);
    } else {
        claim.scryptDependent.scryptFailed(claim.proposalId);

        emit ClaimFailed(claimID, claim.claimant, claim.plaintext, claim.blockHash);
    }
  }

  function claimExists(ScryptClaim storage claim) view private returns(bool) {
    return claim.claimant != address(0x0);
  }

  function firstChallenger(uint claimID) public view returns(address) {
    require(claimID < numClaims);
    return claims[claimID].challengers[0];
  }

  function createdAt(uint claimID) public view returns(uint) {
    //require(claimID < numClaims);
    return claims[claimID].createdAt;
  }

  function getSession(uint claimID, address challenger) public view returns(uint) {
    return claims[claimID].sessions[challenger];
  }

  function getChallengers(uint claimID) public view returns(address[] memory) {
    return claims[claimID].challengers;
  }

  function getCurrentChallenger(uint claimID) public view returns(address) {
    return claims[claimID].challengers[claims[claimID].currentChallenger];
  }

  function getVerificationOngoing(uint claimID) public view returns(bool) {
    return claims[claimID].verificationOngoing;
  }

  function getClaim(uint claimID)
    public
    view
    returns(address claimant, bytes memory plaintext, bytes memory blockHash, bytes32 proposalId)
  {
    ScryptClaim storage claim = claims[claimID];

    return (
      claim.claimant,
      claim.plaintext,
      claim.blockHash,
      claim.proposalId
    );
  }

  function getClaimReady(uint claimID) public view returns(bool) {
    ScryptClaim storage claim = claims[claimID];

    // check that the claim exists
    bool exists = claimExists(claim);

    // check that the claim has exceeded the default challenge timeout.
    bool pastChallengeTimeout = block.number.sub(claim.createdAt) > defaultChallengeTimeout;

    // check that the claim has exceeded the claim's specific challenge timeout.
    bool pastClaimTimeout = block.number > claim.challengeTimeoutBlockNumber;

    // check that there is no ongoing verification game.
    bool noOngoingGames = claim.verificationOngoing == false;

    // check that all verification games have been played.
    bool noPendingGames = claim.numChallengers == claim.currentChallenger;

    return exists && pastChallengeTimeout && pastClaimTimeout && noOngoingGames && noPendingGames;
  }
}

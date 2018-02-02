pragma solidity ^0.4.0;

import {DepositsManager} from './DepositsManager.sol';
import {ScryptVerifier} from "./ScryptVerifier.sol";
import {DogeRelay} from "./DogeRelay.sol";

// ClaimManager: queues a sequence of challengers to play with a claimant.

contract ClaimManager is DepositsManager {
  uint private numClaims = 1;     // index as key for the claims mapping.
  uint public minDeposit = 1;    // TODO: what should the minimum deposit be?

  //default initial amount of blocks for challenge timeout
  uint public defaultChallengeTimeout = 20;

  DogeRelay public dogeRelay;
  ScryptVerifier public scryptVerifier;

  event DepositBonded(uint claimID, address account, uint amount);
  event DepositUnbonded(uint claimID, address account, uint amount);
  event ClaimCreated(uint claimID, address claimant, bytes plaintext, bytes blockHash);
  event ClaimChallenged(uint claimID, address challenger);
  event SessionDecided(uint sessionId, address winner, address loser);
  event ClaimSuccessful(uint claimID, address claimant, bytes plaintext, bytes blockHash);
  event VerificationGameStarted(uint claimID, address claimant, address challenger, uint sessionId);//Rename to SessionStarted?
  event ClaimVerificationGamesEnded(uint claimID);

  struct ScryptClaim {
    address claimant;
    bytes plaintext;    // the plaintext Dogecoin block header.
    bytes blockHash;    // the Dogecoin blockhash.
    uint createdAt;     // the block number at which the claim was created.
    address[] challengers;      // all current challengers.
    mapping(address => uint) sessions; //map challengers to sessionId's
    uint numChallengers;
    uint currentChallenger;    // index of next challenger to play a verification game.
    bool verificationOngoing;   // is the claim waiting for results from an ongoing verificationg game.
    mapping (address => uint) bondedDeposits;   // all deposits bonded in this claim.
    bool decided;
    uint challengeTimeoutBlockNumber;
    bytes32 proposalId;
  }

  mapping(address => uint) public claimantClaims;
  mapping(uint => ScryptClaim) private claims;

  modifier onlyBy(address _account) {
    require(msg.sender == _account);
    _;
  }

    // @dev – the constructor
    function ClaimManager(ScryptVerifier _scryptVerifier) public {
        scryptVerifier = _scryptVerifier;
    }

    //This should be able to only be called once
    function setDogeRelay(DogeRelay _dogeRelay) public {
        require(uint(dogeRelay) == 0x0);
        dogeRelay = _dogeRelay;
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
    DepositBonded(claimID, account, amount);
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
    DepositUnbonded(claimID, account, bondedDeposit);

    return bondedDeposit;
  }

  // @dev – check whether a DogeCoin blockHash was calculated correctly from the plaintext block header.
  // only callable by the DogeRelay contract.
  // @param _plaintext – the plaintext blockHeader.
  // @param _blockHash – the blockHash.
  // @param claimant – the address of the Dogecoin block submitter.
  function checkScrypt(bytes _plaintext, bytes32 _hash, address claimant, bytes32 proposalId) onlyBy(dogeRelay) public payable {
    // dogeRelay can directly make a deposit on behalf of the claimant.
    if (msg.value != 0) {
      // only call if eth is included (to save gas)
      increaseDeposit(claimant, msg.value);
    }

    bytes memory _blockHash = new bytes(32);
    assembly {
        mstore(add(_blockHash, 0x20), _hash)
    }

    require(deposits[claimant] >= minDeposit);
    require(claimantClaims[claimant] == 0);//claimant can only do one claim at a time

    ScryptClaim storage claim = claims[numClaims];
    claim.claimant = claimant;
    claim.plaintext = _plaintext;
    claim.blockHash = _blockHash;
    claim.numChallengers = 0;
    claim.currentChallenger = 0;
    claim.verificationOngoing = false;
    claim.createdAt = block.number;
    claim.decided = false;
    claim.proposalId = proposalId;
    claimantClaims[claimant] = numClaims;

    bondDeposit(numClaims, claimant, minDeposit);
    ClaimCreated(numClaims, claim.claimant, claim.plaintext, claim.blockHash);
    numClaims = numClaims + 1;
  }

  // @dev – challenge an existing Scrypt claim.
  // triggers a downstream claim computation on the scryptVerifier contract
  // where the claimant & the challenger will immediately begin playing a verification.
  //
  // @param claimID – the claim ID.
  function challengeClaim(uint claimID) public {
    //ScryptClaim storage claim = claimantClaims[claimant][claimID]
    ScryptClaim storage claim = claims[claimID];

    require(claimExists(claim));
    require(!claim.decided);
    require(claim.sessions[msg.sender] == 0);

    require(deposits[msg.sender] >= minDeposit);
    bondDeposit(claimID, msg.sender, minDeposit);

    claim.challengeTimeoutBlockNumber = block.number.add(defaultChallengeTimeout);
    claim.challengers.push(msg.sender);
    claim.numChallengers = claim.numChallengers.add(1);
    ClaimChallenged(claimID, msg.sender);
  }

  // @dev – runs a verification game between the claimant and
  // the next queued-up challenger.
  // @param claimID – the claim id.
  function runNextVerificationGame(uint claimID) public {
    ScryptClaim storage claim = claims[claimID];

    require(claimExists(claim));
    require(!claim.decided);

    // check if there is a challenger who has not the played verification game yet.
    if (claim.numChallengers > claim.currentChallenger) {
      require(claim.verificationOngoing == false);

      // kick off a verification game.
      uint sessionId = scryptVerifier.claimComputation(claim.challengers[claim.currentChallenger], claim.claimant, claim.plaintext, claim.blockHash, 2049);
      claim.sessions[claim.challengers[claim.currentChallenger]] = sessionId;
      VerificationGameStarted(claimID, claim.claimant, claim.challengers[claim.currentChallenger], sessionId);

      claim.verificationOngoing = true;
      claim.currentChallenger = claim.currentChallenger.add(1);
    } else {
      require(claim.verificationOngoing == false);
      if (block.number > claim.challengeTimeoutBlockNumber) {
        claim.decided = true;
        ClaimVerificationGamesEnded(claimID);
      }
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
    delete claim.bondedDeposits[loser];
    claim.bondedDeposits[winner] = claim.bondedDeposits[winner].add(depositToTransfer);

    if (claim.claimant == loser) {
      // the claim is over.
      // note: no callback needed to the DogeRelay contract,
      // because it by default does not save blocks.

      //Trigger end of verification game
      claim.numChallengers = 0;
      runNextVerificationGame(claimID);
    } else if (claim.claimant == winner) {
      // the claim continues.
      runNextVerificationGame(claimID);
    } else {
      revert();
    }

    SessionDecided(sessionId, winner, loser);
  }

  // @dev – check whether a claim has successfully withstood all challenges.
  // if successful, it will trigger a callback to the DogeRelay contract,
  // notifying it that the Scrypt blockhash was correctly calculated.
  //
  // @param claimID – the claim ID.
  function checkClaimSuccessful(uint claimID) public {
    ScryptClaim storage claim = claims[claimID];

    require(claimExists(claim));

    // check that the claim has exceeded the default challenge timeout.
    require(block.number.sub(claim.createdAt) > defaultChallengeTimeout);

    //check that the claim has exceeded the claim's specific challenge timeout.
    require(block.number > claim.challengeTimeoutBlockNumber);

    // check that there is no ongoing verification game.
    require(claim.verificationOngoing == false);

    // check that all verification games have been played.
    require(claim.numChallengers == claim.currentChallenger);

    require(claim.decided);

    unbondDeposit(claimID, claim.claimant);
    claimantClaims[claim.claimant] = 0;

    dogeRelay.scryptVerified(claim.proposalId);

    ClaimSuccessful(claimID, claim.claimant, claim.plaintext, claim.blockHash);
  }

  function claimExists(ScryptClaim claim) pure private returns(bool) {
    return claim.claimant != 0x0;
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

  function getChallengers(uint claimID) public view returns(address[]) {
    return claims[claimID].challengers;
  }

  function getCurrentChallenger(uint claimID) public view returns(address) {
    return claims[claimID].challengers[claims[claimID].currentChallenger];
  }

  function getVerificationOngoing(uint claimID) public view returns(bool) {
    return claims[claimID].verificationOngoing;
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
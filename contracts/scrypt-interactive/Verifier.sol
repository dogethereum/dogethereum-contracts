// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
import {ScryptClaims} from "./ScryptClaims.sol";

// Simple generic challenge-response computation verifier.
//
// @TODO:
// * Multiple challangers (proposer should not win just because one challenger fails)
// * Require "gas available" proof for timeout
/**
 * @title Verifier
 * @author Christian Reitwiessner
 */
abstract contract Verifier {
    event NewSession(uint256 sessionId, address claimant, address challenger);
    event NewQuery(uint256 sessionId, address claimant);
    event NewResponse(uint256 sessionId, address challenger);
    event ChallengerConvicted(uint256 sessionId, address challenger);
    event ClaimantConvicted(uint256 sessionId, address claimant);

    // TODO: undo this? Perhaps it should be an immutable value in the constructor
    // so it can be set for test environments.
    //uint constant responseTime = 1 hours;
    uint256 constant responseTime = 10 seconds;

    struct VerificationSession {
        uint256 id;
        address claimant;
        address challenger;
        bytes input;
        bytes output;
        uint256 lastClaimantMessage;
        uint256 lastChallengerMessage;
        uint256 lowStep;
        bytes32 lowHash;
        uint256 medStep;
        bytes32 medHash;
        uint256 highStep;
        bytes32 highHash;
    }

    mapping(uint256 => VerificationSession) public sessions;
    mapping(uint256 => uint256) public sessionsClaimId;
    uint256 sessionsCount;

    function claimComputation(
        uint256 claimId,
        address challenger,
        address claimant,
        bytes memory _input,
        bytes memory _output,
        uint256 steps
    ) public returns (uint256) {
        require(steps > 2, "The computation should have at least two steps.");

        //ScryptClaims constraints don't allow for sessionId 0
        // check if there can be a replay attack with sessionId
        uint256 sessionId = sessionsCount + 1;
        VerificationSession storage s = sessions[sessionId];
        s.id = sessionId;
        sessionsClaimId[sessionId] = claimId;
        s.claimant = claimant;
        s.challenger = challenger;
        s.input = _input;
        s.output = _output;
        s.lastClaimantMessage = block.timestamp;
        s.lastChallengerMessage = block.timestamp;
        s.lowStep = 0;
        s.lowHash = keccak256(_input);
        s.medStep = 0;
        s.medHash = bytes32(0);
        s.highStep = steps;
        s.highHash = keccak256(_output);

        require(isInitiallyValid(s));
        sessionsCount += 1;

        emit NewSession(sessionId, claimant, challenger);
        return sessionId;
    }

    modifier onlyClaimant(uint256 sessionId) {
        require(
            msg.sender == sessions[sessionId].claimant,
            "Only the claimant may call this function."
        );
        _;
    }

    // @TODO(shrugs) - this allows anyone to challenge an empty claim
    //  is this what we want?
    modifier onlyChallenger(uint256 sessionId) {
        VerificationSession storage session = sessions[sessionId];
        require(
            msg.sender == session.challenger,
            "Only the challenger may call this function."
        );
        _;
    }

    function query(uint256 sessionId, uint256 step)
        public
        onlyChallenger(sessionId)
    {
        VerificationSession storage s = sessions[sessionId];

        bool isFirstStep = s.medStep == 0;
        bool haveMedHash = s.medHash != bytes32(0);

        require(
            isFirstStep || haveMedHash,
            "Defender hasn't provided the hash for this step yet"
        );
        // ^ invariant if the step has been set but we don't have a hash for it

        if (step == s.lowStep && step + 1 == s.medStep) {
            // final step of the binary search (lower end)
            s.highHash = s.medHash;
            s.highStep = step + 1;
        } else if (step == s.medStep && step + 1 == s.highStep) {
            // final step of the binary search (upper end)
            s.lowHash = s.medHash;
            s.lowStep = step;
        } else {
            // this next step must be in the correct range
            //can only query between 0...2049
            require(
                s.lowStep < step && step < s.highStep,
                "Step requested is out of bounds"
            );

            // if this is NOT the first query, update the steps and assign the correct hash
            // (if this IS the first query, we just want to initialize medStep and medHash)
            if (!isFirstStep) {
                if (step < s.medStep) {
                    // if we're iterating lower,
                    //   the new highest is the current middle
                    s.highStep = s.medStep;
                    s.highHash = s.medHash;
                } else if (step > s.medStep) {
                    // if we're iterating upwards,
                    //   the new lowest is the current middle
                    s.lowStep = s.medStep;
                    s.lowHash = s.medHash;
                } else {
                    // and if we're requesting the medStep that we've already requested,
                    //   there's nothing to do.
                    // @TODO(shrugs) - should this revert?
                    revert(
                        "Challenger requested for a medStep that was already queried"
                    );
                }
            }

            s.medStep = step;
            s.medHash = bytes32(0);
        }
        s.lastChallengerMessage = block.timestamp;
        emit NewQuery(sessionId, s.claimant);
    }

    function respond(
        uint256 sessionId,
        uint256 step,
        bytes32 hash
    ) public onlyClaimant(sessionId) {
        VerificationSession storage s = sessions[sessionId];
        // Require step to avoid replay problems
        require(step == s.medStep, "Incorrect medStep");

        // provided hash cannot be zero; as that is a special flag.
        require(hash != 0, "Reserved hash value. Hash cannot be 0.");

        // record the claimed hash
        require(s.medHash == bytes32(0), "This step was computed already");
        s.medHash = hash;
        s.lastClaimantMessage = block.timestamp;

        // notify watchers
        emit NewResponse(sessionId, s.challenger);
    }

    function performStepVerification(
        uint256 sessionId,
        uint256 claimId,
        bytes memory preValue,
        bytes memory postValue,
        bytes memory proofs,
        ScryptClaims scryptClaims
    ) public onlyClaimant(sessionId) {
        VerificationSession storage s = sessions[sessionId];
        require(
            s.lowStep + 1 == s.highStep,
            "The step interval must be narrowed down to one step."
        );
        // ^ must be at the end of the binary search according to the smart contract

        // TODO: Is this necessary? Why is the claimId a parameter in this function?
        require(
            claimId == sessionsClaimId[sessionId],
            "The claim ID must be the one associated with this session."
        );

        //prove game ended
        require(
            keccak256(preValue) == s.lowHash,
            "The preimage is not consistent with the claimed hash for the pre-state."
        );
        require(
            keccak256(postValue) == s.highHash,
            "The preimage is not consistent with the claimed hash for the post-state."
        );

        if (
            performStepVerificationSpecific(
                s,
                s.lowStep,
                preValue,
                postValue,
                proofs
            )
        ) {
            challengerConvicted(sessionId, s.challenger, claimId, scryptClaims);
        } else {
            claimantConvicted(sessionId, s.claimant, claimId, scryptClaims);
        }
    }

    function performStepVerificationSpecific(
        VerificationSession storage session,
        uint256 step,
        bytes memory preState,
        bytes memory postState,
        bytes memory proof
    ) internal virtual returns (bool);

    function isInitiallyValid(VerificationSession storage session)
        internal
        virtual
        returns (bool);

    //Able to trigger conviction if time of response is too high
    function timeout(
        uint256 sessionId,
        uint256 claimId,
        ScryptClaims scryptClaims
    ) public {
        VerificationSession storage session = sessions[sessionId];
        // TODO: we may want a way to determine if a session is valid here
        require(session.claimant != address(0));

        if (
            session.lastChallengerMessage > session.lastClaimantMessage &&
            block.timestamp > session.lastChallengerMessage + responseTime
        ) {
            claimantConvicted(
                sessionId,
                session.claimant,
                claimId,
                scryptClaims
            );
        } else if (
            session.lastClaimantMessage > session.lastChallengerMessage &&
            block.timestamp > session.lastClaimantMessage + responseTime
        ) {
            challengerConvicted(
                sessionId,
                session.challenger,
                claimId,
                scryptClaims
            );
        } else {
            revert("Neither the claimant nor the challenger timed out yet.");
        }
    }

    function challengerConvicted(
        uint256 sessionId,
        address challenger,
        uint256 claimId,
        ScryptClaims scryptClaims
    ) internal {
        VerificationSession storage s = sessions[sessionId];
        scryptClaims.sessionDecided(
            sessionId,
            claimId,
            s.claimant,
            s.challenger
        );
        disable(sessionId);
        emit ChallengerConvicted(sessionId, challenger);
    }

    function claimantConvicted(
        uint256 sessionId,
        address claimant,
        uint256 claimId,
        ScryptClaims scryptClaims
    ) internal {
        VerificationSession storage s = sessions[sessionId];
        scryptClaims.sessionDecided(
            sessionId,
            claimId,
            s.challenger,
            s.claimant
        );
        disable(sessionId);
        emit ClaimantConvicted(sessionId, claimant);
    }

    function disable(uint256 sessionId) internal {
        delete sessions[sessionId];
    }

    function getSession(uint256 sessionId)
        public
        view
        returns (
            uint256 lowStep,
            uint256 medStep,
            uint256 highStep,
            bytes memory input,
            bytes32 medHash
        )
    {
        VerificationSession storage session = sessions[sessionId];
        return (
            session.lowStep,
            session.medStep,
            session.highStep,
            session.input,
            session.medHash
        );
    }

    function getLastSteps(uint256 sessionId)
        public
        view
        returns (uint256 lastClaimantMessage, uint256 lastChallengerMessage)
    {
        VerificationSession storage session = sessions[sessionId];
        return (session.lastClaimantMessage, session.lastChallengerMessage);
    }
}

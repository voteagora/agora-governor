// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Hooks} from "src/libraries/Hooks.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";
import {IMiddleware} from "src/interfaces/IMiddleware.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// MACI Objects
import {MACI} from "maci/MACI.sol";
import {Poll} from "maci/Poll.sol";
import {Tally} from "maci/Tally.sol";
import {IPollFactory} from "maci/interfaces/IPollFactory.sol";
import {Params} from "maci/utilities/Params.sol";
import {DomainObjs} from "maci/utilities/DomainObjs.sol";

enum VoteType {
    Against,
    For,
    Abstain
}

struct ProposalSettings {
    DomainObjs.Mode mode; // Quadratic Voting = 0, Non-Quadratic Voting = 1
        // treeDepths(?)
}

struct Proposal {
    address governor;
    address maci;
    address poll;
    address messageProcessor;
    address tally;
    uint256 pollId;
    uint256 timepoint;
}

/// @custom:security-contact security@voteagora.com
contract MACIModule is BaseHook, Params, DomainObjs {
    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/
    uint256 constant MAX_VOTE_OPTIONS = 3; // Only support three voting options: Against = 0, For = 1, Abstain = 2

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ExistingProposal();
    error NotGovernor();
    error InvalidMiddleware();
    error VoteOptionsExceeded();
    error PollCreationFailed();
    error NotTallied();
    error InvalidCastVote();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    IMiddleware public middleware;
    MACI public maci;
    PubKey coordinatorPubKey;
    TreeDepths treeDepths;
    address verifier;
    address vkRegistry;
    uint256 currentPollId;
    uint256 avgBlockTime;

    mapping(uint256 proposalId => Proposal) public proposals;

    /// @notice Reverts if the sender of the hook is not the governor
    modifier onlyGovernor(address sender) {
        if (sender != address(governor)) revert NotGovernor();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address payable _governor,
        address _middleware,
        address _maci,
        PubKey memory _coordinatorPubKey,
        TreeDepths memory _treeDepths,
        address _verifier,
        address _vkRegistry,
        uint256 _avgBlockTime
    ) BaseHook(_governor) {
        if (_middleware == address(0)) revert InvalidMiddleware();
        if (_treeDepths.voteOptionTreeDepth != MAX_VOTE_OPTIONS) revert VoteOptionsExceeded();

        middleware = IMiddleware(_middleware);

        // Core Parameters to create polls for a given MACI instance that can be reused.
        maci = MACI(_maci);
        coordinatorPubKey = _coordinatorPubKey;
        treeDepths = _treeDepths;
        verifier = _verifier;
        vkRegistry = _vkRegistry;
        avgBlockTime = _avgBlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeVoteSucceeded: true,
            afterVoteSucceeded: false,
            beforeQuorumCalculation: true,
            afterQuorumCalculation: true,
            beforeVote: true,
            afterVote: false,
            beforePropose: true,
            afterPropose: false,
            beforeCancel: false,
            afterCancel: false,
            beforeQueue: true,
            afterQueue: false,
            beforeExecute: false,
            afterExecute: false
        });
    }

    function afterPropose(
        address sender,
        uint256 proposalId,
        address[] memory, /*targets*/
        uint256[] memory, /*values*/
        bytes[] memory, /*calldatas*/
        string memory description
    ) external virtual override onlyGovernor(sender) returns (bytes4) {
        if (proposals[proposalId].governor != address(0)) {
            revert ExistingProposal();
        }

        bytes memory proposalData = bytes(description);
        (ProposalSettings memory proposalSettings) = abi.decode(proposalData, (ProposalSettings));

        // Take the governor block number duration and covert it to a timestamp format for MACI Polls
        // Note: this is so that the startTime of the Poll and the Proposal will be different so here we ensure that
        // until the duration of the Poll incorporates the voting delay so it has the expected snapshot value for voice credits
        uint256 timepoint = block.number + governor.votingDelay();
        uint256 duration = (timepoint + governor.votingPeriod()) * avgBlockTime;

        // Deploy Poll
        maci.deployPoll(duration, treeDepths, coordinatorPubKey, verifier, vkRegistry, proposalSettings.mode);

        // Match the pollId in the MACI instance
        uint256 pollId = currentPollId;

        unchecked {
            currentPollId++; // increment for the next proposal to be created
        }

        (address poll, address messageProcessor, address tally) = maci.polls(pollId);

        if (poll == address(0) || messageProcessor == address(0) || tally == address(0)) revert PollCreationFailed();

        proposals[proposalId].governor = address(governor);
        proposals[proposalId].maci = address(maci);
        proposals[proposalId].poll = poll;
        proposals[proposalId].messageProcessor = messageProcessor;
        proposals[proposalId].tally = tally;
        proposals[proposalId].pollId = pollId;
        proposals[proposalId].timepoint = timepoint;

        return (this.afterPropose.selector);
    }

    // quorum ERC20VotesInitialVoiceCreditProxy.sol
    // castVoteWithParams - The user calls THIS module and does not reveal their preference by interfacing with the Governor, calls register at a given timepoint

    // Always reverts, do not cast your votes using the governor interface
    function beforeVote(
        address, /* sender */
        uint256, /* proposalId */
        address, /* account */
        uint8, /* support */
        string memory, /* reason */
        bytes memory /* params */
    ) external override returns (bytes4, bool, uint256) {
        revert InvalidCastVote();
        return (this.afterVote.selector, false, 0);
    }

    /**
     * @dev Return true if at least one option satisfies the passing criteria.
     * Used by governor in `_voteSucceeded`. See {Governor-_voteSucceeded}.
     *
     * @param proposalId The id of the proposal.
     */
    function beforeVoteSucceeded(address sender, uint256 proposalId)
        external
        view
        override
        onlyGovernor(sender)
        returns (bytes4, bool, bool)
    {
        Proposal memory proposal = proposals[proposalId];
        // check the MACI Poll/Tally contract state
        // proposal.poll;
        if (!Tally(proposal.tally).isTallied()) revert NotTallied();

        // TODO: Some contract after publishMessages that reads the results

        return (this.beforeVoteSucceeded.selector, true, false);
    }
}

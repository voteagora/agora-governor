// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Hooks} from "src/libraries/Hooks.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";
import {IMiddleware} from "src/interfaces/IMiddleware.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// MACI Objects
import {MACI} from "maci/MACI.sol";
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
            afterVoteSucceeded: true,
            beforeQuorumCalculation: true,
            afterQuorumCalculation: true,
            beforeVote: true,
            afterVote: true,
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
        (ProposalSettings memory proposalSettings) =
            abi.decode(proposalData, (ProposalSettings));

        // Take the governor block number duration and covert it to a timestamp format for MACI Polls
        // Note: this is so that the startTime of the Poll and the Proposal will be different so here we ensure that
        // until the duration of the Poll incorporates the voting delay so it has the expected snapshot value for voice credits
        uint256 duration = (block.number + governor.votingDelay() + governor.votingPeriod()) * avgBlockTime;

        // Deploy Poll
        maci.deployPoll(
            duration,
            treeDepths,
            coordinatorPubKey,
            verifier,
            vkRegistry,
            proposalSettings.mode
        );

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

        return (this.afterPropose.selector);
    }

    // quorum ERC20VotesInitialVoiceCreditProxy.sol
    // beforeVote Revert
    // castVoteWithParams - The user calls THIS module and does not reveal their preference by interfacing with the Governor
    // beforeVoteSucceeded - check the MACI Poll contract state
    // beforeAfterVoteSucceeded - clean up the proposal state of the governor
}


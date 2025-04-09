// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotesQuorumFraction} from
    "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";

import {IHooks} from "src/interfaces/IHooks.sol";
import {Hooks} from "src/libraries/Hooks.sol";

/// @title AgoraGovernor
/// @notice Agora Governor contract
/// @custom:security-contact security@voteagora.com
contract AgoraGovernor is
    Governor,   
    GovernorCountingSimple,
    GovernorVotesQuorumFraction,
    GovernorSettings,
    GovernorTimelockControl
{
    using Hooks for IHooks;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event AdminSet(address indexed oldAdmin, address indexed newAdmin);
    event ManagerSet(address indexed oldManager, address indexed newManager);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error GovernorUnauthorizedCancel();
    error HookAddressNotValid();
    error ProposalNotSuccessful();
    error ProposalNotQueued();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The admin of the governor
    address public admin;

    /// @notice The manager of the governor
    address public manager;

    /// @notice The hooks of the governor
    IHooks public hooks;

    /// @notice Mapping to maintain state consistency across different IDs
    mapping(uint256 => uint256) private _proposalIdMapping;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        uint48 _votingDelay,
        uint32 _votingPeriod,
        uint256 _proposalThreshold,
        uint256 _quorumNumerator,
        IVotes _token,
        TimelockController _timelock,
        address _admin,
        address _manager,
        IHooks _hooks
    )
        Governor("AgoraGovernor")
        GovernorCountingSimple()
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(_quorumNumerator)
        GovernorSettings(_votingDelay, _votingPeriod, _proposalThreshold)
        GovernorTimelockControl(_timelock)
    {
        if (!_hooks.isValidHookAddress()) revert Hooks.HookAddressNotValid(address(_hooks));

        // This call is made after the inhereted constructors have been called
        _hooks.beforeInitialize();

        admin = _admin;
        manager = _manager;
        hooks = _hooks;

        _hooks.afterInitialize();
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setAdmin(address _newAdmin) external onlyGovernance {
        admin = _newAdmin;
        emit AdminSet(admin, _newAdmin);
    }

    function setManager(address _newManager) external onlyGovernance {
        manager = _newManager;
        emit ManagerSet(manager, _newManager);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override returns (uint256) {
        bytes4 beforeHookSelector;
        uint256 beforeProposalId = 0;
        
        if (address(hooks) != address(0)) {
            (beforeHookSelector, beforeProposalId) = hooks.beforePropose(address(this), targets, values, calldatas, description);
        }
        
        uint256 proposalId = super.propose(targets, values, calldatas, description);
        
        if (address(hooks) != address(0)) {
            hooks.afterPropose(address(this), proposalId, targets, values, calldatas, description);
        }
        
        if(beforeProposalId != 0 && beforeProposalId != proposalId) {
            _proposalIdMapping[beforeProposalId] = proposalId;
        }
        
        return beforeProposalId != 0 ? beforeProposalId : proposalId;
    }

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable virtual override returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        
    
        ProposalState currentState = state(proposalId);
        if(currentState != ProposalState.Queued) {
            revert ProposalNotQueued();
        }
        
        if (address(hooks) != address(0)) {
            (targets, values, calldatas, descriptionHash) = _processExecuteHook(targets, values, calldatas, descriptionHash);
        }
        
        uint256 executedProposalId = super.execute(targets, values, calldatas, descriptionHash);
        
        if (address(hooks) != address(0)) {
            _processAfterExecuteHook(executedProposalId, targets, values, calldatas, descriptionHash);
        }
        
        return executedProposalId;
    }

    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public override returns (uint256) {
        bytes4 beforeHookSelector;
        uint256 beforeProposalId = 0;
        
        if (address(hooks) != address(0)) {
            (beforeHookSelector, beforeProposalId) = hooks.beforeCancel(address(this), targets, values, calldatas, descriptionHash);
        }

        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        address sender = _msgSender();

        if (sender != proposalProposer(proposalId) && sender != admin && sender != _executor()) {
            revert GovernorUnauthorizedCancel();
        }
 
        _cancel(targets, values, calldatas, descriptionHash);

        if (address(hooks) != address(0)) {
            hooks.afterCancel(address(this), proposalId, targets, values, calldatas, descriptionHash);
        }

        return beforeProposalId != 0 ? beforeProposalId : proposalId;
    }

    function quorumDenominator() public pure override returns (uint256) {
        return 10_000;
    }

    function quorum(uint256 _timepoint)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256 _quorum)
    {
        // In a view function, we cannot modify state, so we calculate the quorum directly
        // without calling hooks that could modify state
        _quorum = (token().getPastTotalSupply(_timepoint) * quorumNumerator(_timepoint)) / quorumDenominator();
        
        return _quorum;
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return GovernorTimelockControl.proposalNeedsQueuing(proposalId);
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return GovernorTimelockControl.state(proposalId);
    }

    function proposalThreshold() public view override(GovernorSettings, Governor) returns (uint256) {
        // Return 0 if the caller is the manager to not require voting power when proposing.
        return _msgSender() == manager ? 0 : GovernorSettings.proposalThreshold();
    }

    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual override returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        
        ProposalState currentState = state(proposalId);
        if(currentState != ProposalState.Succeeded) {
            revert ProposalNotSuccessful();
        }
        
        if (address(hooks) != address(0)) {
            (targets, values, calldatas, descriptionHash) = _processQueueHook(targets, values, calldatas, descriptionHash);
        }
        
        uint256 queuedProposalId = super.queue(targets, values, calldatas, descriptionHash);
        
        // Process after hook if hooks are configured
        if (address(hooks) != address(0)) {
            _processAfterQueueHook(queuedProposalId, targets, values, calldatas, descriptionHash);
        }
        
        return queuedProposalId;
    }

    // Helper function to process the beforeQueue hook
    function _processQueueHook(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal returns (
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        bytes32
    ) {
        (bytes4 beforeHookSelector, uint256 beforeProposalId, address[] memory modifiedTargets, uint256[] memory modifiedValues, bytes[] memory modifiedCalldatas, bytes32 modifiedDescriptionHash) = 
            hooks.beforeQueue(address(this), targets, values, calldatas, descriptionHash);
        
        // Use modified parameters if provided by the hook
        if(beforeHookSelector == IHooks.beforeQueue.selector && beforeProposalId != 0) {
            return (modifiedTargets, modifiedValues, modifiedCalldatas, modifiedDescriptionHash);
        }
        
        return (targets, values, calldatas, descriptionHash);
    }

    // Helper function to process the afterQueue hook
    function _processAfterQueueHook(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal {
        hooks.afterQueue(address(this), proposalId, targets, values, calldatas, descriptionHash);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _checkGovernance() internal override {
        // Allow the admin to bypass the governor check.
        if (_msgSender() != admin) {
            super._checkGovernance();
        }
    }

    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        virtual
        override(Governor)
        returns (uint256)
    {
        // Our changes to this function were causing the test to fail
        // The issue is that we should only call beforeVote if we have hooks configured
        // Let's implement a more defensive approach
        
        uint256 beforeWeight = 0;
        bytes4 beforeHookSelector;
        
        if (address(hooks) != address(0)) {
            (beforeHookSelector, beforeWeight) = hooks.beforeVote(address(this), proposalId, account, support, reason, params);
        }
        
        uint256 votedWeight = super._castVote(proposalId, account, support, reason, params);
        
        if (address(hooks) != address(0)) {
            hooks.afterVote(address(this), votedWeight, proposalId, account, support, reason, params);
        }
        
        return beforeWeight != 0 ? beforeWeight : votedWeight;
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return GovernorTimelockControl._cancel(targets, values, calldatas, descriptionHash);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return GovernorTimelockControl._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        GovernorTimelockControl._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _quorumReached(uint256 proposalId)
        internal
        view
        override(Governor, GovernorCountingSimple)
        returns (bool)
    {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);
        return quorum(proposalSnapshot(proposalId)) <= againstVotes + forVotes + abstainVotes;
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return GovernorTimelockControl._executor();
    }

    // Helper function to process the beforeExecute hook
    function _processExecuteHook(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal returns (
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        bytes32
    ) {
        (bytes4 beforeHookSelector, uint256 beforeProposalId, address[] memory modifiedTargets, uint256[] memory modifiedValues, bytes[] memory modifiedCalldatas, bytes32 modifiedDescriptionHash) = 
            hooks.beforeExecute(address(this), targets, values, calldatas, descriptionHash);
        
        if(beforeHookSelector == IHooks.beforeExecute.selector && beforeProposalId != 0) {
            return (modifiedTargets, modifiedValues, modifiedCalldatas, modifiedDescriptionHash);
        }
        
        return (targets, values, calldatas, descriptionHash);
    }

    // Helper function to process the afterExecute hook
    function _processAfterExecuteHook(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal {
        hooks.afterExecute(address(this), proposalId, targets, values, calldatas, descriptionHash);
    }
}

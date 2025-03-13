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
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IHooks} from "src/interfaces/IHooks.sol";
import {Hooks} from "src/libraries/Hooks.sol";

/// @title AgoraGovernor
/// @notice Agora Governor contract
/// @custom:security-contact security@voteagora.com
contract AgoraGovernor is Governor, GovernorCountingSimple, GovernorVotesQuorumFraction, GovernorSettings {
    using Hooks for IHooks;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event AdminSet(address indexed oldAdmin, address indexed newAdmin);
    event ManagerSet(address indexed oldManager, address indexed newManager);
    event TimelockChange(address oldTimelock, address newTimelock);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error GovernorUnauthorizedCancel();
    error HookAddressNotValid();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The admin of the governor
    address public admin;

    /// @notice The manager of the governor
    address public manager;

    /// @notice The hooks of the governor
    IHooks public hooks;

    /// @notice The timelock of the governor
    TimelockController internal _timelock;

    /// @notice The timelock ids of the governor
    mapping(uint256 proposalId => bytes32) internal _timelockIds;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        uint48 _votingDelay,
        uint32 _votingPeriod,
        uint256 _proposalThreshold,
        uint256 _quorumNumerator,
        IVotes _token,
        TimelockController _timelockAddress,
        address _admin,
        address _manager,
        IHooks _hooks
    )
        Governor("AgoraGovernor")
        GovernorCountingSimple()
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(_quorumNumerator)
        GovernorSettings(_votingDelay, _votingPeriod, _proposalThreshold)
    {
        if (!_hooks.isValidHookAddress()) revert Hooks.HookAddressNotValid(address(_hooks));

        // This call is made after the inhereted constructors have been called
        _hooks.beforeInitialize();

        admin = _admin;
        manager = _manager;
        hooks = _hooks;
        _updateTimelock(_timelockAddress);

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
    ) public virtual override returns (uint256 proposalId) {
        proposalId = hooks.beforePropose(targets, values, calldatas, description);

        if (proposalId == 0) {
            proposalId = super.propose(targets, values, calldatas, description);
        }

        hooks.afterPropose(proposalId, targets, values, calldatas, description);
    }

    function queue(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
        public
        virtual
        override
        returns (uint256 proposalId)
    {
        proposalId = hooks.beforeQueue(targets, values, calldatas, descriptionHash);

        if (proposalId == 0) {
            proposalId = super.queue(targets, values, calldatas, descriptionHash);
        }

        hooks.afterQueue(proposalId, targets, values, calldatas, descriptionHash);
    }

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable virtual override returns (uint256 proposalId) {
        proposalId = hooks.beforeExecute(targets, values, calldatas, descriptionHash);

        if (proposalId == 0) {
            proposalId = super.execute(targets, values, calldatas, descriptionHash);
        }

        hooks.afterExecute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public override returns (uint256 proposalId) {
        proposalId = hooks.beforeCancel(targets, values, calldatas, descriptionHash);

        if (proposalId == 0) {
            // The proposalId will be recomputed in the `_cancel` call further down. However we need the value before we
            // do the internal call, because we need to check the proposal state BEFORE the internal `_cancel` call
            // changes it. The `hashProposal` duplication has a cost that is limited, and that we accept.
            proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        }

        address sender = _msgSender();
        // Allow the proposer, admin, or executor (timelock) to cancel.
        if (sender != proposalProposer(proposalId) && sender != admin && sender != _executor()) {
            revert GovernorUnauthorizedCancel();
        }

        // Proposals can only be cancelled in any state other than Canceled, Expired, or Executed.
        _cancel(targets, values, calldatas, descriptionHash);

        hooks.afterCancel(proposalId, targets, values, calldatas, descriptionHash);
    }

    function quorumDenominator() public pure override returns (uint256) {
        return 10_000;
    }

    function quorum(uint256 proposalId)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256 _quorum)
    {
        _quorum = hooks.beforeQuorumCalculation(proposalId);

        if (_quorum == 0) {
            uint256 snapshot = proposalSnapshot(proposalId);
            _quorum = (token().getPastTotalSupply(snapshot) * quorumNumerator(snapshot)) / quorumDenominator();
        }

        hooks.afterQuorumCalculation(proposalId, _quorum);
    }

    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        ProposalState currentState = super.state(proposalId);

        if (currentState != ProposalState.Queued) {
            return currentState;
        }

        bytes32 queueid = _timelockIds[proposalId];
        if (_timelock.isOperationPending(queueid)) {
            return ProposalState.Queued;
        } else if (_timelock.isOperationDone(queueid)) {
            // This can happen if the proposal is executed directly on the timelock.
            return ProposalState.Executed;
        } else {
            // This can happen if the proposal is canceled directly on the timelock.
            return ProposalState.Canceled;
        }
    }

    function proposalThreshold() public view override(GovernorSettings, Governor) returns (uint256) {
        // Return 0 if the caller is the manager to not require voting power when proposing.
        return _msgSender() == manager ? 0 : GovernorSettings.proposalThreshold();
    }

    function timelock() public view virtual returns (address) {
        return address(_timelock);
    }

    function proposalNeedsQueuing(uint256) public view virtual override returns (bool) {
        return true;
    }

    function updateTimelock(TimelockController newTimelock) external virtual onlyGovernance {
        _updateTimelock(newTimelock);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override returns (uint48) {
        uint256 delay = _timelock.getMinDelay();

        bytes32 salt = _timelockSalt(descriptionHash);
        _timelockIds[proposalId] = _timelock.hashOperationBatch(targets, values, calldatas, 0, salt);
        _timelock.scheduleBatch(targets, values, calldatas, 0, salt, delay);

        return SafeCast.toUint48(block.timestamp + delay);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override {
        // execute
        _timelock.executeBatch{value: msg.value}(targets, values, calldatas, 0, _timelockSalt(descriptionHash));
        // cleanup for refund
        delete _timelockIds[proposalId];
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override returns (uint256) {
        uint256 proposalId = super._cancel(targets, values, calldatas, descriptionHash);

        bytes32 timelockId = _timelockIds[proposalId];
        if (timelockId != 0) {
            // cancel
            _timelock.cancel(timelockId);
            // cleanup
            delete _timelockIds[proposalId];
        }

        return proposalId;
    }

    function _executor() internal view virtual override returns (address) {
        return address(_timelock);
    }

    function _updateTimelock(TimelockController newTimelock) private {
        emit TimelockChange(address(_timelock), address(newTimelock));
        _timelock = newTimelock;
    }

    function _timelockSalt(bytes32 descriptionHash) private view returns (bytes32) {
        return bytes20(address(this)) ^ descriptionHash;
    }

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
        returns (uint256 weight)
    {
        _validateStateBitmap(proposalId, _encodeStateBitmap(ProposalState.Active));

        weight = hooks.beforeVote(proposalId, account, support, reason, params);

        if (weight == 0) {
            weight = _getVotes(account, proposalSnapshot(proposalId), params);
        }

        hooks.afterVote(weight, proposalId, account, support, reason, params);

        _countVote(proposalId, account, support, weight, params);

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }

        _tallyUpdated(proposalId);
    }

    function _quorumReached(uint256 proposalId)
        internal
        view
        override(Governor, GovernorCountingSimple)
        returns (bool)
    {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);

        return quorum(proposalId) <= againstVotes + forVotes + abstainVotes;
    }

    /**
     * @inheritdoc Governor
     */
    function _voteSucceeded(uint256 proposalId)
        internal
        view
        virtual
        override(Governor, GovernorCountingSimple)
        returns (bool voteSucceeded)
    {
        uint8 beforeVoteSucceeded = hooks.beforeVoteSucceeded(proposalId);

        if (beforeVoteSucceeded == 0) {
            voteSucceeded = super._voteSucceeded(proposalId);
        } else {
            voteSucceeded = beforeVoteSucceeded == 2;
        }

        hooks.afterVoteSucceeded(proposalId, voteSucceeded);
    }
}

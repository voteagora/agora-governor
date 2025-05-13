// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
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
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
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
    error InvalidModifiedExecution();

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

    /// @notice Stores the mappings of successful proposalIds to their modified executions in the timelock
    mapping(uint256 proposalId => bytes) internal _modifiedExecutions;

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

        _setAdmin(_admin);
        _setManager(_manager);
        _updateTimelock(_timelockAddress);

        hooks = _hooks;

        _hooks.afterInitialize();
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the admin address. Only the admin or timelock can call this function.
     * @param _newAdmin The new admin address.
     */
    function setAdmin(address _newAdmin) external onlyGovernance {
        emit AdminSet(admin, _newAdmin);
        admin = _newAdmin;
    }

    /**
     * @notice Set the manager address. Only the admin or timelock can call this function.
     * @param _newManager The new manager address.
     */
    function setManager(address _newManager) external onlyGovernance {
        emit ManagerSet(manager, _newManager);
        manager = _newManager;
    }

    /**
     * @inheritdoc Governor
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override returns (uint256 proposalId) {
        if (targets.length != values.length || targets.length != calldatas.length || targets.length == 0) {
            revert IGovernor.GovernorInvalidProposalLength(targets.length, calldatas.length, values.length);
        }

        hooks.beforePropose(targets, values, calldatas, description);

        proposalId = _propose(targets, values, calldatas, description, msg.sender);

        hooks.afterPropose(proposalId, targets, values, calldatas, description);
    }

    /**
     * @inheritdoc Governor
     */
    function queue(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
        public
        virtual
        override
        returns (uint256)
    {
        uint256 proposalId = getProposalId(targets, values, calldatas, descriptionHash);

        uint48 etaSeconds;

        _validateStateBitmap(proposalId, _encodeStateBitmap(ProposalState.Succeeded));

        (address[] memory _tempTargets, uint256[] memory _tempValues, bytes[] memory _tempCalldatas,) =
            hooks.beforeQueue(targets, values, calldatas, descriptionHash);

        // Store the modified execution and queue those values to the timelock
        if (_tempTargets.length != 0 && _tempValues.length != 0 && _tempCalldatas.length != 0) {
            _modifiedExecutions[proposalId] = abi.encode(_tempTargets, _tempValues, _tempCalldatas);
            targets = _tempTargets;
            values = _tempValues;
            calldatas = _tempCalldatas;
        }

        etaSeconds = _queueOperations(proposalId, targets, values, calldatas, descriptionHash);

        if (etaSeconds != 0) {
            _proposals[proposalId].etaSeconds = etaSeconds;
            emit ProposalQueued(proposalId, etaSeconds);
        } else {
            revert GovernorQueueNotImplemented();
        }

        hooks.afterQueue(proposalId, targets, values, calldatas, descriptionHash);

        return proposalId;
    }

    /**
     * @inheritdoc Governor
     */
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable virtual override returns (uint256) {
        uint256 proposalId = getProposalId(targets, values, calldatas, descriptionHash);

        _validateStateBitmap(
            proposalId, _encodeStateBitmap(ProposalState.Succeeded) | _encodeStateBitmap(ProposalState.Queued)
        );

        hooks.beforeExecute(targets, values, calldatas, descriptionHash);

        if (_modifiedExecutions[proposalId].length != 0) {
            // Retrieve the stored executions: we assume the module modifies the calldata the same way as beforeQueue
            // They must be non-empty however they are unused as the values in storage actually reflect the state of the timelock
            (address[] memory _tempTargets, uint256[] memory _tempValues, bytes[] memory _tempCalldatas) =
                abi.decode(_modifiedExecutions[proposalId], (address[], uint256[], bytes[]));

            targets = _tempTargets;
            values = _tempValues;
            calldatas = _tempCalldatas;
        }

        // mark as executed before calls to avoid reentrancy
        _proposals[proposalId].executed = true;

        // before execute: register governance call in queue.
        if (_executor() != address(this)) {
            for (uint256 i = 0; i < targets.length; ++i) {
                if (targets[i] == address(this)) {
                    _governanceCall.pushBack(keccak256(calldatas[i]));
                }
            }
        }

        _executeOperations(proposalId, targets, values, calldatas, descriptionHash);

        // after execute: cleanup governance call queue.
        if (_executor() != address(this) && !_governanceCall.empty()) {
            _governanceCall.clear();
        }

        emit ProposalExecuted(proposalId);

        hooks.afterExecute(proposalId, targets, values, calldatas, descriptionHash);

        return proposalId;
    }

    /**
     * @inheritdoc Governor
     */
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public override returns (uint256 proposalId) {
        proposalId = getProposalId(targets, values, calldatas, descriptionHash);
        address sender = _msgSender();
        // Allow the proposer, admin, or executor (timelock) to cancel.
        if (sender != proposalProposer(proposalId) && sender != admin && sender != _executor()) {
            revert GovernorUnauthorizedCancel();
        }

        hooks.beforeCancel(targets, values, calldatas, descriptionHash);

        if (_modifiedExecutions[proposalId].length != 0) {
            // Always check if a proposalId has had modified execution in previous hook calls
            (targets, values, calldatas) = abi.decode(_modifiedExecutions[proposalId], (address[], uint256[], bytes[]));
        }

        // Proposals can only be cancelled in any state other than Canceled, Expired, or Executed.
        _cancel(targets, values, calldatas, descriptionHash);

        hooks.afterCancel(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Max value of `quorum` and `approvalThreshold` in `ProposalType`
     */
    function quorumDenominator() public pure override returns (uint256) {
        return 10_000;
    }

    /**
     * @notice Returns the quorum for a `proposalId`, in terms of number of votes: `supply * numerator / denominator`.
     * @dev Supply is calculated at the proposal snapshot timepoint.
     * @dev Quorum value is derived from `ProposalTypes` in the `Middleware` and can be changed using the `beforeQuorumCalculation` hook.
     */
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

        return _quorum;
    }

    /**
     * @inheritdoc Governor
     */
    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        ProposalState currentState = super.state(proposalId);

        if (currentState != ProposalState.Queued) {
            return currentState;
        }

        bytes32 queueId = _timelockIds[proposalId];
        if (_timelock.isOperationPending(queueId)) {
            return ProposalState.Queued;
        } else if (_timelock.isOperationDone(queueId)) {
            // This can happen if the proposal is executed directly on the timelock.
            return ProposalState.Executed;
        } else {
            // This can happen if the proposal is canceled directly on the timelock.
            return ProposalState.Canceled;
        }
    }

    /**
     * @notice Returns the minimal amount of voting power to create a proposal
     */
    function proposalThreshold() public view override(GovernorSettings, Governor) returns (uint256) {
        // Return 0 if the caller is the manager to not require voting power when proposing.
        return _msgSender() == manager ? 0 : GovernorSettings.proposalThreshold();
    }

    /**
     * @notice Returns the address of the current timelock
     */
    function timelock() public view virtual returns (address) {
        return address(_timelock);
    }

    /**
     * @notice Returns true if the given proposalId is in the Succeded state see IGovernor-ProposalState
     * @param proposalId The id of the proposal to be queued.
     */
    function proposalNeedsQueuing(uint256 proposalId) public view virtual override returns (bool) {
        ProposalState currentState = super.state(proposalId);

        return currentState == ProposalState.Succeeded;
    }

    /**
     * @notice Set the timelock address. Only the existing timelock or the admin can change this value
     * @param newTimelock The new timelock address.
     */
    function updateTimelock(TimelockController newTimelock) external virtual onlyGovernance {
        _updateTimelock(newTimelock);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal virtual override returns (uint256 proposalId) {
        // check description restriction
        if (!_isValidDescriptionForProposer(proposer, description)) {
            revert GovernorRestrictedProposer(proposer);
        }

        // check proposal threshold
        uint256 votesThreshold = proposalThreshold();
        if (proposer != manager && votesThreshold > 0) {
            uint256 proposerVotes = getVotes(proposer, clock() - 1);
            if (proposerVotes < votesThreshold) {
                revert GovernorInsufficientProposerVotes(proposer, proposerVotes, votesThreshold);
            }
        }

        proposalId = getProposalId(targets, values, calldatas, keccak256(bytes(description)));

        if (_proposals[proposalId].voteStart != 0) {
            revert GovernorUnexpectedProposalState(proposalId, state(proposalId), bytes32(0));
        }

        uint256 snapshot = clock() + votingDelay();
        uint256 duration = votingPeriod();

        ProposalCore storage proposal = _proposals[proposalId];
        proposal.proposer = proposer;
        proposal.voteStart = SafeCast.toUint48(snapshot);
        proposal.voteDuration = SafeCast.toUint32(duration);

        emit ProposalCreated(
            proposalId,
            proposer,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            snapshot,
            snapshot + duration,
            description
        );

        // Using a named return variable to avoid stack too deep errors
    }

    function _setAdmin(address _newAdmin) internal {
        emit AdminSet(admin, _newAdmin);
        admin = _newAdmin;
    }

    function _setManager(address _newManager) internal {
        emit ManagerSet(manager, _newManager);
        manager = _newManager;
    }

    // @notice See Governor.sol replicates the logic to handle modified calldata from hooks
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

    // @notice See Governor.sol replicates the logic to handle modified calldata from hooks
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

    // @notice See Governor.sol replicates the logic to handle modified calldata from hooks
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

    /**
     * @inheritdoc Governor
     */
    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        virtual
        override(Governor)
        returns (uint256 weight)
    {
        _validateStateBitmap(proposalId, _encodeStateBitmap(ProposalState.Active));
        bool hasUpdated = false;

        (hasUpdated, weight) = hooks.beforeVote(proposalId, account, support, reason, params);

        if (!hasUpdated) {
            weight = _getVotes(account, proposalSnapshot(proposalId), params);
        }

        _countVote(proposalId, account, support, weight, params);

        hooks.afterVote(weight, proposalId, account, support, reason, params);

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }

        _tallyUpdated(proposalId);
    }

    /**
     * @inheritdoc Governor
     */
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

        if (beforeVoteSucceeded == 1) {
            voteSucceeded = super._voteSucceeded(proposalId);
        } else {
            voteSucceeded = beforeVoteSucceeded == 2;
        }

        hooks.afterVoteSucceeded(proposalId, voteSucceeded);
    }
}

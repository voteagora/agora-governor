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
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The admin of the governor
    address public admin;

    /// @notice The manager of the governor
    address public manager;

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
        address _manager
    )
        Governor("AgoraGovernor")
        GovernorCountingSimple()
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(_quorumNumerator)
        GovernorSettings(_votingDelay, _votingPeriod, _proposalThreshold)
        GovernorTimelockControl(_timelock)
    {
        admin = _admin;
        manager = _manager;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function quorum(uint256 _timepoint)
        public
        view
        virtual
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return (token().getPastTotalSupply(_timepoint) * quorumNumerator(_timepoint)) / quorumDenominator();
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

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _checkGovernance() internal override {
        // Allow the admin to bypass the governor check.
        if (_msgSender() != admin) {
            super._checkGovernance();
        }
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

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return GovernorTimelockControl._executor();
    }
}

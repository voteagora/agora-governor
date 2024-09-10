// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IVotes} from "@openzeppelin/contracts-v4/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts-v4/governance/TimelockController.sol";
import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";
import {AgoraGovernor} from "src/AgoraGovernor.sol";

// Expose internal functions for testing
contract AgoraGovernorMock is AgoraGovernor {
    constructor(
        IVotes _token,
        address _admin,
        address _manager,
        TimelockController _timelock,
        IProposalTypesConfigurator _proposalTypesConfigurator,
        IProposalTypesConfigurator.ProposalType[] memory _proposalTypes
    ) AgoraGovernor(_token, _admin, _manager, _timelock, _proposalTypesConfigurator, _proposalTypes) {}

    function quorumReached(uint256 proposalId) public view returns (bool) {
        return _quorumReached(proposalId);
    }

    function voteSucceeded(uint256 proposalId) public view returns (bool) {
        return _voteSucceeded(proposalId);
    }
}

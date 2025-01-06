// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {AgoraGovernor} from "src/AgoraGovernor.sol";
import {IHooks} from "src/interfaces/IHooks.sol";

// Expose internal functions for testing
contract AgoraGovernorMock is AgoraGovernor {
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
        AgoraGovernor(
            _votingDelay,
            _votingPeriod,
            _proposalThreshold,
            _quorumNumerator,
            _token,
            _timelock,
            _admin,
            _manager,
            IHooks(address(0))
        )
    {}

    function quorumReached(uint256 proposalId) public view returns (bool) {
        return _quorumReached(proposalId);
    }

    function voteSucceeded(uint256 proposalId) public view returns (bool) {
        return _voteSucceeded(proposalId);
    }

    // Exclude from coverage report
    function test() public virtual {}
}

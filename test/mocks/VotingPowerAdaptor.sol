// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "src/hooks/BaseHook.sol";
import {Hooks} from "src/libraries/Hooks.sol";

interface MyCustomToken {
    /// @dev Return the voting power of the user at the given block.
    /// @param user The address of the user to get the voting power of.
    /// @param timepoint The timepoint to get voting power at.
    function getLockedVotingPower(address user, uint256 timepoint) external view returns (uint256);
}

contract VotingPowerAdaptor is BaseHook {
    MyCustomToken public immutable token;

    constructor(address payable _governor, address _token) BaseHook(_governor) {
        token = MyCustomToken(_token);
    }

    /// @dev Return the voting power of the custom token. This function can use any of the given parameters
    /// to calculate the voting power to return (and even revert!).
    function beforeVote(address, uint256 proposalId, address voter, uint8, string memory, bytes memory)
        external
        virtual
        override
        returns (bytes4, uint256)
    {
        // Get the proposal snapshot timepoint.
        uint256 snapshot = governor.proposalSnapshot(proposalId);

        // Return the voting power of the user at the snapshot timepoint.
        return (this.beforeVote.selector, token.getLockedVotingPower(voter, snapshot));
    }

    /// @dev Set `beforeVote` permission to get the call before applying a user's vote.
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeVoteSucceeded: false,
            afterVoteSucceeded: false,
            beforeQuorumCalculation: false,
            afterQuorumCalculation: false,
            beforeVote: true,
            afterVote: false,
            beforePropose: false,
            afterPropose: false,
            beforeCancel: false,
            afterCancel: false,
            beforeQueue: false,
            afterQueue: false,
            beforeExecute: false,
            afterExecute: false
        });
    }
}

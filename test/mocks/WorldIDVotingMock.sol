// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {WorldIDVoting, IWorldID} from "src/modules/WorldIDVoting.sol";
import {Proposal, ProposalOption, ProposalSettings} from "src/modules/WorldIDVoting.sol";

// Expose internal functions for testing
contract WorldIDVotingMock is WorldIDVoting {
    constructor(address payable _governor, address _router, IWorldID _worldId, string memory _appId)
        WorldIDVoting(_governor, _router, _worldId, _appId)
    {}

    function _proposals(uint256 proposalId) public view returns (Proposal memory) {
        return proposals[proposalId];
    }
}

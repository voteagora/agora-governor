// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OptimisticExecution} from "src/modules/OptimisticExecution.sol";
import {Proposal, ProposalSettings} from "src/modules/OptimisticExecution.sol";

// Expose internal functions for testing
contract OptimisticExecutionMock is OptimisticExecution {
    constructor(address _governor) OptimisticExecution(_governor) {}

    function _proposals(uint256 proposalId) public view returns (Proposal memory) {
        return proposals[proposalId];
    }
}

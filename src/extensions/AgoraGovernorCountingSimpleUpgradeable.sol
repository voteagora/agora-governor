// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GovernorCountingSimpleUpgradeable} from
    "@openzeppelin/contracts-upgradeable-v4/governance/extensions/GovernorCountingSimpleUpgradeable.sol";

contract AgoraGovernorCountingSimpleUpgradeable is GovernorCountingSimpleUpgradeable {
    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     * Params encoding:
     * - modules = custom external params depending on module used
     */
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=against,for,abstain&params=modules";
    }

    /**
     * @dev Updated version in which quorum is based on `proposalId` instead of snapshot block.
     */
    function _quorumReached(uint256 proposalId) internal view virtual override returns (bool) {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);

        return quorum(proposalId) <= againstVotes + forVotes + abstainVotes;
    }

    /**
     * @dev Added logic based on approval voting threshold to determine if vote has succeeded.
     */
    function _voteSucceeded(uint256 proposalId) internal view virtual override returns (bool voteSucceeded) {
        ProposalCore storage proposal = _proposals[proposalId];

        address votingModule = proposal.votingModule;
        if (votingModule != address(0)) {
            if (!VotingModule(votingModule)._voteSucceeded(proposalId)) {
                return false;
            }
        }

        uint256 approvalThreshold = PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposal.proposalType).approvalThreshold;

        if (approvalThreshold == 0) return true;

        ProposalVote storage proposalVote = _proposalVotes[proposalId];
        uint256 forVotes = proposalVote.forVotes;
        uint256 totalVotes = forVotes + proposalVote.againstVotes;

        if (totalVotes != 0) {
            voteSucceeded = (forVotes * PERCENT_DIVISOR) / totalVotes >= approvalThreshold;
        }
    }
}

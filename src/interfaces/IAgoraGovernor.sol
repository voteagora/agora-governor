// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/VotesUpgradeable.sol";

abstract contract IAgoraGovernor is IGovernor {
    function manager() external view virtual returns (address);
    function admin() external view virtual returns (address);
    function timelock() external view virtual returns (address);

    function PROPOSAL_TYPES_CONFIGURATOR() external view virtual returns (address);

    function token() external view virtual returns (VotesUpgradeable);

    function getProposalType(uint256 proposalId) external view virtual returns (uint8);

    function proposalVotes(uint256 proposalId)
        external
        view
        virtual
        returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes);
}

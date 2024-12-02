// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/VotesUpgradeable.sol";

interface IVotingToken is VotesUpgradeable {
    /// @dev Return the votable supply at a given block number.
    function getPastVotableSupply(uint256 timepoint) external view returns (uint256);
}

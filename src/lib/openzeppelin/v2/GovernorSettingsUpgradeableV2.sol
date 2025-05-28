// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (governance/extensions/GovernorSettings.sol)

pragma solidity ^0.8.0;

import "./GovernorUpgradeableV2.sol";
import "@openzeppelin/contracts-upgradeable-v4/proxy/utils/Initializable.sol";

/**
 * Modifications:
 * - Inherited `GovernorUpgradeableV2`
 */
abstract contract GovernorSettingsUpgradeableV2 is Initializable, GovernorUpgradeableV2 {
    uint256 private _votingDelay;
    uint256 private _votingPeriod;
    uint256 private _proposalThreshold;
    uint256 private _votingDelayInSeconds;
    uint256 private _votingPeriodInSeconds;

    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event VotingDelayInSecondsSet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodInSecondsSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);

    /**
     * @dev Initialize the governance parameters.
     */
    function __GovernorSettings_init(
        uint256 initialVotingDelay,
        uint256 initialVotingPeriod,
        uint256 initialProposalThreshold
    ) internal onlyInitializing {
        __GovernorSettings_init_unchained(initialVotingDelay, initialVotingPeriod, initialProposalThreshold);
    }

    function __GovernorSettings_init_unchained(
        uint256 initialVotingDelay,
        uint256 initialVotingPeriod,
        uint256 initialProposalThreshold
    ) internal onlyInitializing {
        _setVotingDelay(initialVotingDelay);
        _setVotingPeriod(initialVotingPeriod);
        _setProposalThreshold(initialProposalThreshold);
    }

    /**
     * @dev See {IGovernor-votingDelay}.
     */
    function votingDelay() public view virtual override returns (uint256) {
        return _votingDelay;
    }

    /**
     * @dev See {IGovernor-votingPeriod}.
     */
    function votingPeriod() public view virtual override returns (uint256) {
        return _votingPeriod;
    }

    function votingDelayInSeconds() public view virtual returns (uint256) {
        return _votingDelayInSeconds;
    }

    function votingPeriodInSeconds() public view virtual returns (uint256) {
        return _votingPeriodInSeconds;
    }

    /**
     * @dev See {Governor-proposalThreshold}.
     */
    function proposalThreshold() public view virtual override returns (uint256) {
        return _proposalThreshold;
    }

    /**
     * @dev Update the voting delay. This operation can only be performed through a governance proposal.
     *
     * Emits a {VotingDelaySet} event.
     */
    function setVotingDelay(uint256 newVotingDelay) public virtual onlyGovernance {
        _setVotingDelay(newVotingDelay);
    }

    /**
     * @dev Update the voting period. This operation can only be performed through a governance proposal.
     *
     * Emits a {VotingPeriodSet} event.
     */
    function setVotingPeriod(uint256 newVotingPeriod) public virtual onlyGovernance {
        _setVotingPeriod(newVotingPeriod);
    }

    /**
     * @dev Update the voting delay in seconds. This operation can only be performed through a governance proposal.
     *
     * Emits a {VotingDelayInSecondsSet} event.
     */
    function setVotingDelayInSeconds(uint256 newVotingDelay) public virtual onlyGovernance {
        _setVotingDelayInSeconds(newVotingDelay);
    }

    /**
     * @dev Update the voting period in seconds. This operation can only be performed through a governance proposal.
     *
     * Emits a {VotingPeriodInSecondsSet} event.
     */
    function setVotingPeriodInSeconds(uint256 newVotingPeriod) public virtual onlyGovernance {
        _setVotingPeriodInSeconds(newVotingPeriod);
    }

    /**
     * @dev Update the proposal threshold. This operation can only be performed through a governance proposal.
     *
     * Emits a {ProposalThresholdSet} event.
     */
    function setProposalThreshold(uint256 newProposalThreshold) public virtual onlyGovernance {
        _setProposalThreshold(newProposalThreshold);
    }

    /**
     * @dev Internal setter for the voting delay.
     *
     * Emits a {VotingDelaySet} event.
     */
    function _setVotingDelay(uint256 newVotingDelay) internal virtual {
        emit VotingDelaySet(_votingDelay, newVotingDelay);
        _votingDelay = newVotingDelay;
    }

    /**
     * @dev Internal setter for the voting period.
     *
     * Emits a {VotingPeriodSet} event.
     */
    function _setVotingPeriod(uint256 newVotingPeriod) internal virtual {
        // voting period must be at least one block long
        require(newVotingPeriod > 0, "GovernorSettings: voting period too low");
        emit VotingPeriodSet(_votingPeriod, newVotingPeriod);
        _votingPeriod = newVotingPeriod;
    }

    /**
     * @dev Internal setter for the voting delay in seconds.
     *
     * Emits a {VotingDelayInSecondsSet} event.
     */
    function _setVotingDelayInSeconds(uint256 newVotingDelayInSeconds) internal virtual {
        emit VotingDelayInSecondsSet(_votingDelayInSeconds, newVotingDelayInSeconds);
        _votingDelayInSeconds = newVotingDelayInSeconds;
    }

    /**
     * @dev Internal setter for the voting period in seconds.
     *
     * Emits a {VotingPeriodTimestampSet} event.
     */
    function _setVotingPeriodInSeconds(uint256 newVotingPeriodInSeconds) internal virtual {
        // voting period must be at least one second long
        require(newVotingPeriodInSeconds > 0, "GovernorSettings: voting period too low");

        emit VotingPeriodInSecondsSet(_votingPeriodInSeconds, newVotingPeriodInSeconds);
        _votingPeriodInSeconds = newVotingPeriodInSeconds;
    }

    /**
     * @dev Internal setter for the proposal threshold.
     *
     * Emits a {ProposalThresholdSet} event.
     */
    function _setProposalThreshold(uint256 newProposalThreshold) internal virtual {
        emit ProposalThresholdSet(_proposalThreshold, newProposalThreshold);
        _proposalThreshold = newProposalThreshold;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}

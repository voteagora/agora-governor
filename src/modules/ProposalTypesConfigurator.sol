// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";
import {AgoraGovernor} from "src/AgoraGovernor.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {Hooks} from "src/libraries/Hooks.sol";
import {BaseHook} from "src/BaseHook.sol";

contract ProposalTypesConfigurator is IProposalTypesConfigurator, BaseHook {
    using Hooks for IHooks;
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ScopeCreated(uint8 indexed proposalTypeId, bytes24 indexed scopeKey, bytes4 selector, string description);
    event ScopeDisabled(uint8 indexed proposalTypeId, bytes24 indexed scopeKey);

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Max value of `quorum` and `approvalThreshold` in `ProposalType`
    uint16 public constant PERCENT_DIVISOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint8 proposalTypeId => ProposalType) internal _proposalTypes;

    mapping(uint8 proposalTypeId => mapping(bytes24 key => Scope[])) internal _assignedScopes;
    mapping(bytes24 key => bool) internal _scopeExists;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAdminOrTimelock() {
        if (msg.sender != governor.admin() && msg.sender != governor.timelock()) revert NotAdminOrTimelock();
        _;
    }

    constructor(address payable _governor) BaseHook(_governor) {
        for (uint8 i = 0; i < _proposalTypesInit.length; i++) {
            _setProposalType(
                i,
                _proposalTypesInit[i].quorum,
                _proposalTypesInit[i].approvalThreshold,
                _proposalTypesInit[i].name,
                _proposalTypesInit[i].description,
                _proposalTypesInit[i].module
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeQuorumCalculation: false,
            afterQuorumCalculation: true,
            beforeVote: false,
            afterVote: false,
            beforePropose: true,
            afterPropose: true, // set voting threshold
            beforeCancel: false,
            afterCancel: false,
            beforeQueue: false,
            afterQueue: false,
            beforeExecute: false,
            afterExecute: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                               HOOKS
    //////////////////////////////////////////////////////////////*/

    /// @notice The hook called before quorum calculation is performed
    function beforeQuorumCalculation(address sender, uint256 timepoint) external override view returns (bytes4, uint256) {
        uint256 _beforeQuorum =
            (governor.token().getPastTotalSupply(timepoint) * _proposalTypes[0].quorum) / governor.quorumDenominator();
        return (IHooks.beforeQuorumCalculation.selector, _beforeQuorum);
    }

    // remove timepoint (either call the governor or some other hook), just use proposalId

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Set the parameters for a proposal type. Only callable by the admin or timelock.
     * @param proposalTypeId Id of the proposal type
     * @param quorum Quorum percentage, scaled by `PERCENT_DIVISOR`
     * @param approvalThreshold Approval threshold percentage, scaled by `PERCENT_DIVISOR`
     * @param name Name of the proposal type
     * @param description Describes the proposal type
     * @param module Address of module that can only use this proposal type
     */
    function setProposalType(
        uint8 proposalTypeId,
        uint16 quorum,
        uint16 approvalThreshold,
        string calldata name,
        string calldata description,
        address module
    ) external override onlyAdminOrTimelock {
        _setProposalType(proposalTypeId, quorum, approvalThreshold, name, description, module);
    }

    function _setProposalType(
        uint8 proposalTypeId,
        uint16 quorum,
        uint16 approvalThreshold,
        string calldata name,
        string calldata description,
        address module
    ) internal {
        if (quorum > PERCENT_DIVISOR) revert InvalidQuorum();
        if (approvalThreshold > PERCENT_DIVISOR) revert InvalidApprovalThreshold();

        _proposalTypes[proposalTypeId] = ProposalType(quorum, approvalThreshold, name, description, module, true);

        emit ProposalTypeSet(proposalTypeId, quorum, approvalThreshold, name, description);
    }
}

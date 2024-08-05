// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";
import {IAgoraGovernor} from "src/interfaces/IAgoraGovernor.sol";

/**
 * Contract that stores proposalTypes for  Governor.
 */
contract ProposalTypesConfigurator is IProposalTypesConfigurator {
    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    IAgoraGovernor public governor;
    uint16 public constant PERCENT_DIVISOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint8 proposalTypeId => ProposalType) internal _proposalTypes;
    mapping(uint8 proposalTypeId => bool) internal _proposalTypesExists;
    mapping(uint8 proposalTypeId => Scope[]) public scopes;
	mapping(uint8 proposalTypeId => mapping(bytes32 typeHash => bool)) public scopeExists;
	mapping(bytes32 typeHash => bytes32 limits) public limits;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAdminOrTimelock() {
        if (msg.sender != governor.admin() && msg.sender != governor.timelock()) revert NotAdminOrTimelock();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != governor.admin()) revert NotAdmin();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the contract with the governor and proposal types.
     * @param _governor Address of the governor contract.
     * @param _proposalTypesInit Array of ProposalType structs to initialize the contract with.
     */
    function initialize(address _governor, ProposalType[] calldata _proposalTypesInit) external {
        if (address(governor) != address(0)) revert AlreadyInit();
        governor = IAgoraGovernor(_governor);
        for (uint8 i = 0; i < _proposalTypesInit.length; i++) {
            _setProposalType(
                i,
                _proposalTypesInit[i].quorum,
                _proposalTypesInit[i].approvalThreshold,
                _proposalTypesInit[i].name,
                _proposalTypesInit[i].module,
                _proposalTypesInit[i].txTypeHashes
            );
        }
    }

    /**
     * @notice Get the parameters for a proposal type.
     * @param proposalTypeId Id of the proposal type.
     * @return ProposalType struct of of the proposal type.
     */
    function proposalTypes(uint8 proposalTypeId) external view override returns (ProposalType memory) {
        return _proposalTypes[proposalTypeId];
    }

    /**
     * @notice Sets the scope for a given proposal type.
     * @param proposalTypeId Id of the proposal type.
     */
    function setScopeForProposalType(
        uint8 proposalTypeId,
        bytes32 txTypeHash,
        bytes32 encodedLimit,
        bytes[] memory parameters,
	    Comparators[] memory comparators
    ) external override onlyAdmin {
        _setScopeForProposalType(proposalTypeId, txTypeHash, encodedLimit, parameters, comparators);
    }

    function _setScopeForProposalType(
        uint8 proposalTypeId,
        bytes32 txTypeHash,
        bytes32 encodedLimit,
        bytes[] memory parameters,
	    Comparators[] memory comparators
    ) internal {
        if(!_proposalTypesExists[proposalTypeId]) revert InvalidProposalType();
        if(parameters.length != comparators.length) revert InvalidParameterConditions();

        Scope memory scope = Scope(txTypeHash, encodedLimit, parameters, comparators);
        scopes[proposalTypeId].push(scope);

        scopeExists[proposalTypeId][txTypeHash] = true;
    }

    /**
     * @notice Set the parameters for a proposal type. Only callable by the admin or timelock.
     * @param proposalTypeId Id of the proposal type
     * @param quorum Quorum percentage, scaled by `PERCENT_DIVISOR`
     * @param approvalThreshold Approval threshold percentage, scaled by `PERCENT_DIVISOR`
     * @param name Name of the proposal type
     * @param module Address of module that can only use this proposal type
     */
    function setProposalType(
        uint8 proposalTypeId,
        uint16 quorum,
        uint16 approvalThreshold,
        string calldata name,
        address module,
        bytes32[] memory txTypeHashes
    ) external override onlyAdminOrTimelock {
        _setProposalType(proposalTypeId, quorum, approvalThreshold, name, module, txTypeHashes);
    }

    function _setProposalType(
        uint8 proposalTypeId,
        uint16 quorum,
        uint16 approvalThreshold,
        string calldata name,
        address module,
        bytes32[] memory txTypeHashes
    ) internal {
        if (quorum > PERCENT_DIVISOR) revert InvalidQuorum();
        if (approvalThreshold > PERCENT_DIVISOR) revert InvalidApprovalThreshold();

        _proposalTypes[proposalTypeId] = ProposalType(quorum, approvalThreshold, name, module, txTypeHashes);
        _proposalTypesExists[proposalTypeId] = true;

        emit ProposalTypeSet(proposalTypeId, quorum, approvalThreshold, name, txTypeHashes);
    }
}

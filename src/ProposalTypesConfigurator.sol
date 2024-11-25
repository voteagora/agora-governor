// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";
import {IAgoraGovernor} from "src/interfaces/IAgoraGovernor.sol";
import {Validator} from "src/Validator.sol";

/**
 * Contract that stores proposalTypes for the Agora Governor.
 * @custom:security-contact security@voteagora.com
 */
contract ProposalTypesConfigurator is IProposalTypesConfigurator {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ScopeCreated(uint8 indexed proposalTypeId, bytes24 indexed scopeKey, bytes4 selector, string description);
    event ScopeDisabled(uint8 indexed proposalTypeId, bytes24 indexed scopeKey);

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    IAgoraGovernor public governor;

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
        if (_governor == address(0)) revert InvalidGovernor();

        governor = IAgoraGovernor(_governor);

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

    /**
     * @notice Get the parameters for a proposal type.
     * @param proposalTypeId Id of the proposal type.
     * @return ProposalType struct of of the proposal type.
     */
    function proposalTypes(uint8 proposalTypeId) external view returns (ProposalType memory) {
        return _proposalTypes[proposalTypeId];
    }

    /**
     * @notice Get the scope that is assigned to a given proposal type.
     * @param proposalTypeId Id of the proposal type.
     * @param scopeKey The function selector + contract address that is the key for a scope.
     * @return Scope struct of the scope.
     */
    function assignedScopes(uint8 proposalTypeId, bytes24 scopeKey) external view returns (Scope[] memory) {
        return _assignedScopes[proposalTypeId][scopeKey];
    }

    /**
     * @notice Returns a boolean if a scope exists.
     * @param key A function selector and contract address that represent the type hash, i.e. 4byte(keccak256("foobar(uint,address)")) + bytes20(contractAddress).
     * @return boolean returns true if the scope is defined.
     */
    function scopeExists(bytes24 key) external view override returns (bool) {
        return _scopeExists[key];
    }

    /**
     * @notice Sets the scope for a given proposal type.
     * @param proposalTypeId Id of the proposal type.
     * @param key A function selector and contract address that represent the type hash, i.e. 4byte(keccak256("foobar(uint,address)")) + bytes20(contractAddress).
     * @param selector A 4 byte function selector.
     * @param parameters The list of byte represented values to be compared.
     * @param comparators List of enumuerated values represent which comparison to use when enforcing limit checks on parameters.
     * @param types List of enumuerated types that map onto each of the supplied parameters.
     * @param description String that's the describes the scope
     */
    function setScopeForProposalType(
        uint8 proposalTypeId,
        bytes24 key,
        bytes4 selector,
        bytes[] memory parameters,
        Comparators[] memory comparators,
        SupportedTypes[] memory types,
        string calldata description
    ) external override onlyAdminOrTimelock {
        if (!_proposalTypes[proposalTypeId].exists) revert InvalidProposalType();
        if (parameters.length != comparators.length) revert InvalidParameterConditions();

        Scope memory scope = Scope(key, selector, parameters, comparators, types, proposalTypeId, description, true);
        _assignedScopes[proposalTypeId][key].push(scope);
        _scopeExists[key] = true;

        emit ScopeCreated(proposalTypeId, key, selector, description);
    }

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

        emit ProposalTypeSet(proposalTypeId, quorum, approvalThreshold, name, description, module);
    }

    /**
     * @notice Adds an additional scope for a given proposal type.
     * @param proposalTypeId Id of the proposal type
     * @param scope An object that contains the scope for a transaction type hash
     */
    function addScopeForProposalType(uint8 proposalTypeId, Scope calldata scope)
        external
        override
        onlyAdminOrTimelock
    {
        if (!_proposalTypes[proposalTypeId].exists) revert InvalidProposalType();
        if (scope.parameters.length != scope.comparators.length) revert InvalidParameterConditions();
        bytes24 scopeKey = scope.key;

        _scopeExists[scope.key] = true;
        _assignedScopes[proposalTypeId][scope.key].push(scope);

        emit ScopeCreated(proposalTypeId, scope.key, scope.selector, scope.description);
    }

    /**
     * @notice Retrives the function selector of a transaction for a given proposal type.
     * @param proposalTypeId Id of the proposal type
     * @param key A type signature of a function and contract address that has a limit specified in a scope
     */
    function getSelector(uint8 proposalTypeId, bytes24 key) public view returns (bytes4 selector) {
        if (!_proposalTypes[proposalTypeId].exists) revert InvalidProposalType();
        Scope memory validScope = _assignedScopes[proposalTypeId][key][0];
        return validScope.selector;
    }

    /**
     * @notice Disables a scopes for all contract + function signatures.
     * @param proposalTypeId the proposal type ID that has the assigned scope.
     * @param scopeKey the contract and function signature representing the scope key
     * @param idx the index of the assigned scope.
     */
    function disableScope(uint8 proposalTypeId, bytes24 scopeKey, uint8 idx) external override onlyAdminOrTimelock {
        _assignedScopes[proposalTypeId][scopeKey][idx].exists = false;
        emit ScopeDisabled(proposalTypeId, scopeKey);
    }

    /**
     * @notice Validates that a proposed transaction conforms to the scope defined in a given proposal type. Note: This
     *   version only supports functions that have for each parameter 32-byte abi encodings, please see the ABI
     *   specification to see which types are not supported. The types that are supported are as follows:
     *      - Uint
     *      - Address
     *      - Bytes32
     * @param proposedTx The calldata of the proposed transaction
     * @param proposalTypeId Id of the proposal type
     * @param key A type signature of a function and contract address that has a limit specified in a scope
     */
    function validateProposedTx(bytes calldata proposedTx, uint8 proposalTypeId, bytes24 key) public view {
        Scope[] memory scopes = _assignedScopes[proposalTypeId][key];

        if (_scopeExists[key]) {
            for (uint8 i = 0; i < scopes.length; i++) {
                Scope memory validScope = scopes[i];
                if (validScope.selector != bytes4(proposedTx[:4])) revert Invalid4ByteSelector();

                uint256 startIdx = 4;
                uint256 endIdx = startIdx;
                for (uint8 j = 0; j < validScope.parameters.length; j++) {
                    endIdx = endIdx + validScope.parameters[j].length;

                    Validator.determineValidation(
                        proposedTx[startIdx:endIdx],
                        validScope.parameters[j],
                        validScope.types[j],
                        validScope.comparators[j]
                    );

                    startIdx = endIdx;
                }
            }
        }
    }

    /**
     * @notice Validates the proposed transactions against the defined scopes based on the proposal type
     * proposal threshold can propose.
     * @param targets The list of target contract addresses.
     * @param calldatas The list of proposed transaction calldata.
     * @param proposalTypeId The type of the proposal.
     */
    function validateProposalData(address[] memory targets, bytes[] calldata calldatas, uint8 proposalTypeId)
        external
        view
    {
        for (uint8 i = 0; i < calldatas.length; i++) {
            bytes24 scopeKey = _pack(targets[i], bytes4(calldatas[i]));
            if (_assignedScopes[proposalTypeId][scopeKey].length != 0) {
                validateProposedTx(calldatas[i], proposalTypeId, scopeKey);
            } else {
                if (_scopeExists[scopeKey]) {
                    revert InvalidProposedTxForType();
                }
            }
        }
    }

    /**
     * @notice Generates the scope key defined as the contract address combined with the function selector
     * @param contractAddress Address of the contract to be enforced by the scope
     * @param selector A byte4 function selector on the contract to be enforced by the scope
     */
    function _pack(address contractAddress, bytes4 selector) internal pure returns (bytes24 result) {
        bytes20 left = bytes20(contractAddress);
        assembly ("memory-safe") {
            left := and(left, shl(96, not(0)))
            selector := and(selector, shl(224, not(0)))
            result := or(left, shr(160, selector))
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";
import {IAgoraGovernor} from "src/interfaces/IAgoraGovernor.sol";
import {ScopeKey} from "src/ScopeKey.sol";

/**
 * Contract that stores proposalTypes for the Agora Governor.
 */
contract ProposalTypesConfigurator is IProposalTypesConfigurator {
    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    using ScopeKey for bytes24;
    IAgoraGovernor public governor;
    uint16 public constant PERCENT_DIVISOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint8 proposalTypeId => ProposalType) internal _proposalTypes;
    mapping(uint8 proposalTypeId => bool) internal _proposalTypesExists;
    mapping(uint8 proposalTypeId => mapping(bytes24 key => Scope)) public assignedScopes;
    // mapping(uint8 proposalTypeId => mapping(bytes32 typeHash => bool)) public scopeExists;
    Scope[] public scopes;


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
                _proposalTypesInit[i].description,
                _proposalTypesInit[i].module,
                _proposalTypesInit[i].validScopes
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
     * @param key A function selector and contract address that represent the type hash, i.e. 4byte(keccak256("foobar(uint,address)")) + bytes20(contractAddress).
     * @param encodedLimit An ABI encoded string containing the function selector and relevant parameter values.
     * @param parameters The list of byte represented values to be compared against the encoded limits.
     * @param comparators List of enumuerated values represent which comparison to use when enforcing limit checks on parameters.
     */
    function setScopeForProposalType(
        uint8 proposalTypeId,
        bytes24 key,
        bytes calldata encodedLimit,
        bytes[] memory parameters,
        Comparators[] memory comparators
    ) external override onlyAdmin {
        if (!_proposalTypesExists[proposalTypeId]) revert InvalidProposalType();
        if (parameters.length != comparators.length) revert InvalidParameterConditions();
        if (assignedScopes[proposalTypeId][key].exists) revert NoDuplicateTxTypes(); // Do not allow multiple scopes for a single transaction type

        for (uint8 i = 0; i < _proposalTypes[proposalTypeId].validScopes.length; i++) {
            if (_proposalTypes[proposalTypeId].validScopes[i] == key) {
                revert NoDuplicateTxTypes();
            }
        }

        Scope memory scope = Scope(key, encodedLimit, parameters, comparators, proposalTypeId, true);
        scopes.push(scope);

        assignedScopes[proposalTypeId][key] = scope;
        _proposalTypes[proposalTypeId].validScopes.push(key);
    }

    /**
     * @notice Set the parameters for a proposal type. Only callable by the admin or timelock.
     * @param proposalTypeId Id of the proposal type
     * @param quorum Quorum percentage, scaled by `PERCENT_DIVISOR`
     * @param approvalThreshold Approval threshold percentage, scaled by `PERCENT_DIVISOR`
     * @param name Name of the proposal type
     * @param description Describes the proposal type
     * @param module Address of module that can only use this proposal type
     * @param validScopes A list of function selector and contract address that represent the type hash, i.e. 4byte(keccak256("foobar(uint,address)")) + bytes20(contractAddress).
     */
    function setProposalType(
        uint8 proposalTypeId,
        uint16 quorum,
        uint16 approvalThreshold,
        string calldata name,
        string calldata description,
        address module,
        bytes24[] memory validScopes
    ) external override onlyAdminOrTimelock {
        _setProposalType(proposalTypeId, quorum, approvalThreshold, name, description, module, validScopes);
    }

    function _setProposalType(
        uint8 proposalTypeId,
        uint16 quorum,
        uint16 approvalThreshold,
        string calldata name,
        string calldata description,
        address module,
        bytes24[] memory validScopes
    ) internal {
        if (quorum > PERCENT_DIVISOR) revert InvalidQuorum();
        if (approvalThreshold > PERCENT_DIVISOR) revert InvalidApprovalThreshold();

        _proposalTypes[proposalTypeId] =
            ProposalType(quorum, approvalThreshold, name, description, module, validScopes);
        _proposalTypesExists[proposalTypeId] = true;

        emit ProposalTypeSet(proposalTypeId, quorum, approvalThreshold, name, description, validScopes);
    }

    /**
     * @notice Adds an additional scope for a given proposal type.
     * @param proposalTypeId Id of the proposal type
     * @param scope An object that contains the scope for a transaction type hash
     */
    function updateScopeForProposalType(uint8 proposalTypeId, Scope calldata scope) external override onlyAdmin {
        if (!_proposalTypesExists[proposalTypeId]) revert InvalidProposalType();
        if (scope.parameters.length != scope.comparators.length) revert InvalidParameterConditions();
        if (assignedScopes[proposalTypeId][scope.key].exists) revert NoDuplicateTxTypes(); // Do not allow multiple scopes for a single transaction type

        scopes.push(scope);
        assignedScopes[proposalTypeId][scope.key] = scope;
    }

    /**
     * @notice Retrives the encoded limit of a transaction type signature for a given proposal type.
     * @param proposalTypeId Id of the proposal type
     * @param key A type signature of a function and contract address that has a limit specified in a scope
     */
    function getLimit(uint8 proposalTypeId, bytes24 key) public view returns (bytes memory encodedLimits) {
        if (!_proposalTypesExists[proposalTypeId]) revert InvalidProposalType();
        if (!assignedScopes[proposalTypeId][key].exists) revert InvalidScope();
        Scope memory validScope = assignedScopes[proposalTypeId][key];
        return validScope.encodedLimits;
    }

    /**
     * @dev Given the limitation that these byte values are stored in memory, this function allows us to use the slice syntax given that the parameter field
     * contains the correct byte length. Note that the way slice indices are handled such that [startIdx, endIdx)
     * @notice This will retrieve the parameter from the encoded transaction.
     * @param limit The abi.encodedWithSignature that contains the limits with parameters i.e abi.encodedWithSignature('functionSelector(a,b)', _a, _b)
     * @param startIdx The start index in the byte array that contains the parameter, inclusive.
     * @param endIdx The end index in the byte array that contains parameter exclusive
     */
    function getParameter(bytes calldata limit, uint256 startIdx, uint256 endIdx)
        public
        pure
        returns (bytes memory parameter)
    {
        return limit[startIdx:endIdx + 1];
    }

    function validateProposedTx(bytes calldata proposedTx, uint8 proposalTypeId, bytes24 key)
        public
        view
        returns (bool valid)
    {
        Scope memory validScope = assignedScopes[proposalTypeId][key];
        bytes memory scopeLimit = validScope.encodedLimits;
        bytes4 selector = bytes4(scopeLimit);
        if (selector != bytes4(proposedTx[:4])) revert Invalid4ByteSelector();

        uint256 startIdx = 4;
        uint256 endIdx = startIdx;
        for (uint8 i = 0; i < validScope.parameters.length; i++) {
            endIdx = endIdx + validScope.parameters[i].length;

            bytes32 param = bytes32(proposedTx[startIdx:endIdx]);

            if (validScope.comparators[i] == Comparators.EQUAL) {
                bytes32 scopedParam = bytes32(this.getParameter(scopeLimit, startIdx, endIdx));
                if (scopedParam != param) revert InvalidParamNotEqual();
            }

            if (validScope.comparators[i] == Comparators.LESS_THAN) {
                if (param >= bytes32(validScope.parameters[i])) revert InvalidParamRange();
            }

            if (validScope.comparators[i] == Comparators.GREATER_THAN) {
                if (param <= bytes32(validScope.parameters[i])) revert InvalidParamRange();
            }

            if (validScope.comparators[i] == Comparators.EMPTY) {
                // do nothing for now?
            }

            startIdx = endIdx;
        }

        return true;
    }
}

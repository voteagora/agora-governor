// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IMiddleware} from "src/interfaces/IMiddleware.sol";
import {AgoraGovernor} from "src/AgoraGovernor.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {Hooks} from "src/libraries/Hooks.sol";
import {Parser} from "src/libraries/Parser.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";

import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Validator} from "src/libraries/Validator.sol";

/// @title Middleware
/// @notice Middleware contract to handle hooks interface
/// @custom:security-contact security@voteagora.com
/// @dev This contract serves as a routing mechanism between proposal types and their corresponding hook modules. It
//  forwards calls made from the governor to the submodules like ApprovalVoting and ensures the hook actually implements
//  the function prior to making the call. Furthermore, the middleware contract is responsible for Scopes, a seperate
//  feature that during the `beforePropose` step validates the targets and calldata supplied and ensures that the
//  proposal type is allowed to make such a transaction. We assume that scopes will not be configured with certain
//  modules like Approval which modify execution state.
contract Middleware is IMiddleware, BaseHook {
    using Hooks for IHooks;
    using Parser for string;

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

    // @notice Max length of the `assignedScopes` array
    uint8 public constant MAX_SCOPE_LENGTH = 5;

    error BeforeExecuteFailed();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint8 proposalTypeId => ProposalType) internal _proposalTypes;
    mapping(uint8 proposalTypeId => mapping(bytes24 key => Scope[])) internal _assignedScopes;
    mapping(bytes24 key => bool) internal _scopeExists;
    mapping(uint256 proposalId => uint8 proposalTypeId) internal _proposalTypeId;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAdminOrTimelock() {
        if (msg.sender != governor.admin() && msg.sender != governor.timelock()) {
            revert NotAdminOrTimelock();
        }
        _;
    }

    constructor(address payable _governor) BaseHook(_governor) {}

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc BaseHook
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeVoteSucceeded: true,
            afterVoteSucceeded: true,
            beforeQuorumCalculation: true,
            afterQuorumCalculation: true,
            beforeVote: true,
            afterVote: true,
            beforePropose: true,
            afterPropose: true,
            beforeCancel: true,
            afterCancel: true,
            beforeQueue: true,
            afterQueue: true,
            beforeExecute: true,
            afterExecute: true
        });
    }

    /*//////////////////////////////////////////////////////////////
                               HOOKS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHooks
    function beforeVoteSucceeded(address sender, uint256 proposalId)
        external
        view
        override
        returns (bytes4, bool voteSucceeded)
    {
        uint8 proposalTypeId = _proposalTypeId[proposalId];
        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.beforeVoteSucceeded) {
            (, voteSucceeded) = BaseHook(module).beforeVoteSucceeded(msg.sender, proposalId);
        }

        return (this.beforeVoteSucceeded.selector, voteSucceeded);
    }

    /// @inheritdoc IHooks
    function afterVoteSucceeded(address sender, uint256 proposalId, bool voteSucceeded)
        external
        view
        override
        returns (bytes4)
    {
        uint8 proposalTypeId = _proposalTypeId[proposalId];
        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.afterVoteSucceeded) {
            BaseHook(module).afterVoteSucceeded(msg.sender, proposalId, voteSucceeded);
        }

        return this.afterVoteSucceeded.selector;
    }

    /// @inheritdoc IHooks
    function beforeQuorumCalculation(address sender, uint256 proposalId)
        external
        view
        override
        returns (bytes4, uint256)
    {
        uint256 calculatedQuorum;
        uint8 proposalTypeId = _proposalTypeId[proposalId];
        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.beforeQuorumCalculation) {
            (, calculatedQuorum) = BaseHook(module).beforeQuorumCalculation(msg.sender, proposalId);
        } else {
            calculatedQuorum = (
                governor.token().getPastTotalSupply(governor.proposalSnapshot(proposalId))
                    * _proposalTypes[proposalTypeId].quorum
            ) / governor.quorumDenominator();
        }
        // Return the quorum from the proposal type
        return (this.beforeQuorumCalculation.selector, calculatedQuorum);
    }

    /// @inheritdoc IHooks
    function afterQuorumCalculation(address sender, uint256 proposalId, uint256 quorum)
        external
        view
        override
        returns (bytes4)
    {
        uint8 proposalTypeId = _proposalTypeId[proposalId];
        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.afterQuorumCalculation) {
            BaseHook(module).afterQuorumCalculation(msg.sender, proposalId, quorum);
        }

        return this.afterQuorumCalculation.selector;
    }

    /// @inheritdoc IHooks
    function beforeVote(
        address sender,
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) external override returns (bytes4, bool hasUpdated, uint256 weight) {
        uint8 proposalTypeId = _proposalTypeId[proposalId];
        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.beforeVote) {
            (, hasUpdated, weight) =
                BaseHook(module).beforeVote(msg.sender, proposalId, account, support, reason, params);
        }

        return (this.beforeVote.selector, hasUpdated, weight);
    }

    /// @inheritdoc IHooks
    function afterVote(
        address sender,
        uint256 weight,
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) external override returns (bytes4) {
        uint8 proposalTypeId = _proposalTypeId[proposalId];
        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.afterVote) {
            BaseHook(module).afterVote(msg.sender, weight, proposalId, account, support, reason, params);
        }

        return this.afterVote.selector;
    }

    /// @inheritdoc IHooks
    function beforePropose(
        address sender,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external virtual override returns (bytes4, uint256) {
        uint256 proposalId;
        uint8 proposalTypeId = description._parseProposalTypeId();
        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.beforePropose) {
            string memory proposalData = description._parseProposalData();
            (, proposalId) = BaseHook(module).beforePropose(msg.sender, targets, values, calldatas, proposalData);
        }

        // `this` is required to convert `calldatas` from memory to calldata
        this.validateProposalData(targets, calldatas, proposalTypeId);

        proposalId = governor.hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        _proposalTypeId[proposalId] = proposalTypeId;

        return (this.beforePropose.selector, proposalId);
    }

    /// @inheritdoc IHooks
    function afterPropose(
        address sender,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external virtual override returns (bytes4) {
        uint8 proposalTypeId = _proposalTypeId[proposalId];
        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.afterPropose) {
            string memory proposalData = description._parseProposalData();
            BaseHook(module).afterPropose(msg.sender, proposalId, targets, values, calldatas, proposalData);
        }

        return this.afterPropose.selector;
    }

    /// @inheritdoc IHooks
    function beforeCancel(
        address sender,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external override returns (bytes4, uint256) {
        uint256 proposalId = governor.hashProposal(targets, values, calldatas, descriptionHash);
        uint8 proposalTypeId = _proposalTypeId[proposalId];
        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.beforeCancel) {
            (, proposalId) = BaseHook(module).beforeCancel(msg.sender, targets, values, calldatas, descriptionHash);
        }
        return (this.beforeCancel.selector, proposalId);
    }

    /// @inheritdoc IHooks
    function afterCancel(
        address sender,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external override returns (bytes4) {
        uint8 proposalTypeId = _proposalTypeId[proposalId];
        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.afterCancel) {
            BaseHook(module).afterCancel(msg.sender, proposalId, targets, values, calldatas, descriptionHash);
        }

        return this.afterCancel.selector;
    }

    /// @inheritdoc IHooks
    function beforeQueue(
        address sender,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external override returns (bytes4, uint256, address[] memory, uint256[] memory, bytes[] memory, bytes32) {
        uint256 proposalId = governor.hashProposal(targets, values, calldatas, descriptionHash);
        uint8 proposalTypeId = _proposalTypeId[proposalId];
        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.beforeQueue) {
            (, proposalId, targets, values, calldatas, descriptionHash) =
                BaseHook(module).beforeQueue(msg.sender, targets, values, calldatas, descriptionHash);
        }

        return (this.beforeQueue.selector, proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @inheritdoc IHooks
    function afterQueue(
        address sender,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external override returns (bytes4) {
        uint8 proposalTypeId = _proposalTypeId[proposalId];
        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.afterQueue) {
            BaseHook(module).afterQueue(msg.sender, proposalId, targets, values, calldatas, descriptionHash);
        }

        return this.afterQueue.selector;
    }

    /// @inheritdoc IHooks
    function beforeExecute(
        address sender,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external override returns (bytes4, bool) {
        bool success = true;
        uint256 proposalId = governor.hashProposal(targets, values, calldatas, descriptionHash);
        uint8 proposalTypeId = _proposalTypeId[proposalId];

        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.beforeExecute) {
            (, success) = BaseHook(module).beforeExecute(msg.sender, targets, values, calldatas, descriptionHash);
        }

        if (!success) revert BeforeExecuteFailed();

        return (this.beforeExecute.selector, success);
    }

    /// @inheritdoc IHooks
    function afterExecute(
        address sender,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external override returns (bytes4) {
        uint8 proposalTypeId = _proposalTypeId[proposalId];
        _proposalTypeExists(proposalTypeId);

        address module = _proposalTypes[proposalTypeId].module;
        Hooks.Permissions memory hooks = BaseHook(module).getHookPermissions();

        // Route hook to voting module
        if (module != address(0) && hooks.afterExecute) {
            BaseHook(module).afterExecute(msg.sender, proposalId, targets, values, calldatas, descriptionHash);
        }

        return this.afterExecute.selector;
    }

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the parameters for a proposal type.
     * @param proposalTypeId Id of the proposal type.
     * @return ProposalType struct of of the proposal type.
     */
    function proposalTypes(uint8 proposalTypeId) external view returns (ProposalType memory) {
        return _proposalTypes[proposalTypeId];
    }

    /**
     * @notice Get the proposalType for a given proposalId.
     * @param proposalId Id of the proposal
     */
    function getProposalTypeId(uint256 proposalId) external view returns (uint8) {
        return _proposalTypeId[proposalId];
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
     * @notice Retrives the function selector of a transaction for a given proposal type.
     * @param proposalTypeId Id of the proposal type
     * @param key A type signature of a function and contract address that has a limit specified in a scope
     */
    function getSelector(uint8 proposalTypeId, bytes24 key) public view returns (bytes4 selector) {
        if (!_scopeExists[key]) revert InvalidScope();
        if (!_proposalTypes[proposalTypeId].exists) revert InvalidProposalType();
        Scope memory validScope = _assignedScopes[proposalTypeId][key][0];
        return validScope.selector;
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
        if (_assignedScopes[proposalTypeId][key].length == MAX_SCOPE_LENGTH) revert MaxScopeLengthReached();

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
        string memory name,
        string memory description,
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
        if (_assignedScopes[proposalTypeId][scope.key].length == MAX_SCOPE_LENGTH) revert MaxScopeLengthReached();

        _scopeExists[scope.key] = true;
        _assignedScopes[proposalTypeId][scope.key].push(scope);

        emit ScopeCreated(proposalTypeId, scope.key, scope.selector, scope.description);
    }

    /**
     * @notice Disables a scopes for all contract + function signatures.
     * @param proposalTypeId the proposal type ID that has the assigned scope.
     * @param scopeKey the contract and function signature representing the scope key
     * @param idx the index of the assigned scope.
     */
    function disableScope(uint8 proposalTypeId, bytes24 scopeKey, uint8 idx) external override onlyAdminOrTimelock {
        _assignedScopes[proposalTypeId][scopeKey][idx].exists = false;
        _scopeExists[scopeKey] = false;
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
                if (validScope.selector != bytes4(proposedTx[:4])) {
                    revert Invalid4ByteSelector();
                }

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

    function _proposalTypeExists(uint8 proposalTypeId) internal view {
        // Revert if `proposalType` is unset
        if (!_proposalTypes[proposalTypeId].exists) {
            revert InvalidProposalType();
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IProposalTypesConfigurator {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidQuorum();
    error InvalidApprovalThreshold();
    error InvalidProposalType();
    error InvalidParameterConditions();
    error InvalidScope();
    error NotAdminOrTimelock();
    error NotAdmin();
    error InvalidGovernor();
    error Invalid4ByteSelector();
    error InvalidParamNotEqual();
    error InvalidParamRange();
    error InvalidProposedTxForType();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalTypeSet(
        uint8 indexed proposalTypeId, uint16 quorum, uint16 approvalThreshold, string name, string description
    );

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct ProposalType {
        uint16 quorum;
        uint16 approvalThreshold;
        string name;
        string description;
        address module;
        bool exists;
    }

    enum Comparators {
        EMPTY,
        EQUAL,
        LESS_THAN,
        GREATER_THAN
    }

    enum SupportedTypes {
        NONE,
        UINT8,
        UINT16,
        UINT32,
        UINT64,
        UINT128,
        UINT256,
        ADDRESS,
        BYTES32
    }

    struct Scope {
        bytes24 key;
        bytes4 selector;
        bytes[] parameters;
        Comparators[] comparators;
        SupportedTypes[] types;
        uint8 proposalTypeId;
        string description;
        bool exists;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function proposalTypes(uint8 proposalTypeId) external view returns (ProposalType memory);
    function assignedScopes(uint8 proposalTypeId, bytes24 scopeKey) external view returns (Scope[] memory);
    function scopeExists(bytes24 key) external view returns (bool);

    function setProposalType(
        uint8 proposalTypeId,
        uint16 quorum,
        uint16 approvalThreshold,
        string memory name,
        string memory description,
        address module
    ) external;

    function setScopeForProposalType(
        uint8 proposalTypeId,
        bytes24 key,
        bytes4 selector,
        bytes[] memory parameters,
        Comparators[] memory comparators,
        SupportedTypes[] memory types,
        string memory description
    ) external;

    function getSelector(uint8 proposalTypeId, bytes24 key) external returns (bytes4);
    function addScopeForProposalType(uint8 proposalTypeId, Scope calldata scope) external;
    function disableScope(uint8 proposalTypeId, bytes24 scopeKey, uint8 idx) external;
    function validateProposedTx(bytes calldata proposedTx, uint8 proposalTypeId, bytes24 key) external;
    function validateProposalData(address[] memory targets, bytes[] memory calldatas, uint8 proposalTypeId) external;
}

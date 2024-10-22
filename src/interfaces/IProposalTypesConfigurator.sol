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
    error NoDuplicateTxTypes();
    error InvalidScope();
    error NotAdminOrTimelock();
    error NotAdmin();
    error AlreadyInit();
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
    }

    enum Comparators {
        EMPTY,
        EQUAL,
        LESS_THAN,
        GREATER_THAN
    }

    struct Scope {
        bytes24 key;
        bytes encodedLimits;
        bytes[] parameters;
        Comparators[] comparators;
        uint8 proposalTypeId;
        string description;
        bool exists;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function initialize(address _governor, ProposalType[] calldata _proposalTypes) external;

    function proposalTypes(uint8 proposalTypeId) external view returns (ProposalType memory);
    function assignedScopes(uint8 proposalTypeId, bytes24 scopeKey) external view returns (Scope memory);
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
        bytes calldata encodedLimit,
        bytes[] memory parameters,
        Comparators[] memory comparators,
        string memory description
    ) external;

    function updateScopeForProposalType(uint8 proposalTypeId, Scope calldata scope) external;
    function getLimit(uint8 proposalTypeId, bytes24 key) external returns (bytes memory);
    function validateProposedTx(bytes calldata proposedTx, uint8 proposalTypeId, bytes24 key) external;
    function validateProposalData(address[] memory targets, bytes[] memory calldatas, uint8 proposalType) external;
}

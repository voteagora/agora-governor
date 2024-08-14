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

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalTypeSet(
        uint8 indexed proposalTypeId, uint16 quorum, uint16 approvalThreshold, string name, bytes32[] txTypeHashes
    );

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct ProposalType {
        uint16 quorum;
        uint16 approvalThreshold;
        string name;
        address module;
        bytes32[] txTypeHashes;
    }

    enum Comparators {
        EMPTY,
        EQUAL,
        LESS_THAN,
        GREATER_THAN
    }

    struct Scope {
        bytes32 txTypeHash;
        bytes encodedLimits;
        bytes[] parameters;
        Comparators[] comparators;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function initialize(address _governor, ProposalType[] calldata _proposalTypes) external;

    function proposalTypes(uint8 proposalTypeId) external view returns (ProposalType memory);

    function setProposalType(
        uint8 proposalTypeId,
        uint16 quorum,
        uint16 approvalThreshold,
        string memory name,
        address module,
        bytes32[] memory txTypeHashes
    ) external;

    function setScopeForProposalType(
        uint8 proposalTypeId,
        bytes32 txTypeHash,
        bytes calldata encodedLimit,
        bytes[] memory parameters,
        Comparators[] memory comparators
    ) external;

    function updateScopeForProposalType(uint8 proposalTypeId, Scope calldata scope) external;
    function getLimit(uint8 proposalTypeId, bytes32 txTypeHash) external returns (bytes memory);
}

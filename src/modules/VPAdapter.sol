// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Hooks} from "src/libraries/Hooks.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";

// import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
// import {Merkle} from "@murky/Merkle.sol";

struct Proposal {
    address governor;
    uint256 quorum;
    bytes32 vpRoot;
}

/// @custom:security-contact security@voteagora.com
contract VPAdapter is BaseHook {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotGovernor();
    error ExistingProposal();
    error InvalidProof();

    // event ProposalCreated();

    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public admin;
    mapping(uint256 proposalId => Proposal) public proposals;
    mapping(uint256 proposalId => uint256) public quorums;
    mapping(uint256 proposalId => bytes32) public merkleRoots;

    bytes32 lastestRoot;
    uint256 latestQuorum;

    uint256 lastUpdatedBlock;
    uint256 merkleRootDuration;

    // mapping(uint256 proposalId => mapping(address account => EnumerableSet.UintSet votes)) private accountVotesSet;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts if the sender of the hook is not the governor
    modifier onlyGovernor(address sender) {
        if (sender != address(governor)) revert NotGovernor();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address payable _governor, address _admin) BaseHook(_governor) {
        admin = _admin;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeVoteSucceeded: true,
            afterVoteSucceeded: false,
            beforeQuorumCalculation: true,
            afterQuorumCalculation: false,
            beforeVote: true,
            afterVote: false,
            beforePropose: true,
            afterPropose: true,
            beforeCancel: false,
            afterCancel: false,
            beforeQueue: true,
            afterQueue: false,
            beforeExecute: false,
            afterExecute: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                                 HOOKS
    //////////////////////////////////////////////////////////////*/

    function afterPropose(
        address sender,
        uint256 proposalId,
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        string memory description
    ) external virtual override onlyGovernor(sender) returns (bytes4) {
        if (proposals[proposalId].governor != address(0)) {
            revert ExistingProposal();
        }

        proposals[proposalId].governor = sender;
        proposals[proposalId].quorum = latestQuorum;
        proposals[proposalId].vpRoot = lastestRoot;

        // emit ProposalCreated(proposalId);

        return BaseHook.afterPropose.selector;
    }

    function beforeVote(
        address sender,
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) external override onlyGovernor(sender) returns (bytes4, bool, uint256 weight) {
        (uint256 _weight, bytes32[] memory _merkleProof) = abi.decode(params, (uint256, bytes32[]));

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account, _weight))));

        // Verify the merkle proof
        if (!MerkleProof.verify(_merkleProof, lastestRoot, leaf)) revert InvalidProof();

        return (this.beforeVote.selector, true, _weight);
    }

    /**
     * Used by governor in `_voteSucceeded`. See {Governor-_voteSucceeded}.
     *
     * @param proposalId The id of the proposal.
     */
    function beforeVoteSucceeded(address sender, uint256 proposalId)
        external
        view
        override
        onlyGovernor(sender)
        returns (bytes4, bool, bool)
    {
        Proposal memory proposal = proposals[proposalId];
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        // Use stored quorum value
        bool succeded = proposal.quorum <= againstVotes + forVotes + abstainVotes;

        return (this.beforeVoteSucceeded.selector, true, succeded);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Defines the encoding for the expected `proposalData` in `propose`.
     * Encoding: `()`
     *
     * @dev Can be used by clients to interact with modules programmatically without prior knowledge
     * on expected types.
     */
    function PROPOSAL_DATA_ENCODING() external pure virtual returns (string memory) {
        return "()";
    }

    /**
     * Module version.
     */
    function version() public pure returns (uint256) {
        return 1;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
}

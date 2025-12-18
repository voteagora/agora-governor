// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Hooks} from "src/libraries/Hooks.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";

// import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

struct Proposal {
    address governor;
    uint256 quorum;
    bytes32 vpRoot;
    uint256 expectedBlock;
    uint256 startBlock;
}

/// @custom:security-contact security@voteagora.com
contract VPAdapter is BaseHook {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotGovernor();
    error NotAdmin();
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
    mapping(uint256 proposalId => uint256) public merkleRoots;

    mapping(uint256 => bytes32) public thresholdRoots;

    bytes32 public latestRoot;
    uint256 public latestQuorum;

    uint256 public lastUpdatedBlock;
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

    modifier onlyAdmin(address sender) {
        if (sender != address(admin)) revert NotAdmin();
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
            beforeQuorumCalculation: false,
            afterQuorumCalculation: false,
            beforeVote: true,
            afterVote: false,
            beforePropose: false,
            afterPropose: true,
            beforeCancel: false,
            afterCancel: false,
            beforeQueue: false,
            afterQueue: false,
            beforeExecute: false,
            afterExecute: false
        });
    }

    function setMerkleRoot(bytes32 newRoot) public onlyAdmin(msg.sender) {
        latestRoot = newRoot;
        lastUpdatedBlock = block.number;

        thresholdRoots[lastUpdatedBlock] = latestRoot;
    }

    function setQuorum(uint256 newQuorum) public onlyAdmin(msg.sender) {
        latestQuorum = newQuorum;
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
        proposals[proposalId].expectedBlock = block.number + (IGovernor(sender).votingDelay() / 2);
        proposals[proposalId].startBlock = block.number;

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
        require(proposals[proposalId].startBlock < lastUpdatedBlock);
        require(lastUpdatedBlock <= proposals[proposalId].expectedBlock);

        (uint256 _weight, bytes32[] memory _merkleProof) = abi.decode(params, (uint256, bytes32[]));

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account, _weight))));

        // Verify the merkle proof
        if (!MerkleProof.verify(_merkleProof, latestRoot, leaf)) revert InvalidProof();

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

    function verifyThreshold(address proposer, uint256 weight, bytes32[] memory merkleProof)
        public
        view
        returns (bool)
    {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(proposer, weight))));
        return MerkleProof.verify(merkleProof, latestRoot, leaf);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
}

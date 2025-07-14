// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Hooks} from "src/libraries/Hooks.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

interface IWorldID {
    function verifyProof(
        uint256 root,
        uint256 signalHash,
        uint256 groupId,
        uint256 nullifierHash,
        uint256 externalNullifierHash,
        uint256[8] calldata proof
    ) external view;
}

library ByteHasher {
    /// @dev Creates a keccak256 hash of a bytestring.
    /// @param value The bytestring to hash
    /// @return The hash of the specified value
    /// @dev `>> 8` makes sure that the result is included in our field
    function hashToField(bytes memory value) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(value))) >> 8;
    }
}

/// GovernorBravo VotingType
enum VoteType {
    Against,
    For,
    Abstain
}

/// Approval voting criteria and 1P1V for single option calldata
enum PassingCriteria {
    Threshold,
    TopChoices,
    Standard
}

/// No execution Approval Voting option
struct ProposalOption {
    string description;
}

/// Proposal configuration that sets the voting criteria and the relevant voting parameters to move proposals into the succeeded state
struct ProposalSettings {
    uint256 minParticipation;
    /// Minimum number of users that must cast their vote in Standard voting
    uint8 maxApprovals;
    uint8 criteria;
    uint128 criteriaValue;
    bool isSignalVote;
    string actionId;
}

/// Proposal Tally and Metadata
struct Proposal {
    address governor;
    ProposalSettings settings;
    ProposalOption[] options;
    uint128[] optionVotes;
    uint256 forVotes;
    uint256 againstVotes;
    uint256 externalNullifierHash;
}

/// @custom:security-contact security@voteagora.com
contract WorldIDVoting is BaseHook {
    error NotGovernor();
    error NotRouter();
    error ExistingProposal();
    // Approval Voting Errors
    error MaxChoicesExceeded();
    error MaxApprovalsExceeded();
    error OptionsNotStrictlyAscending();
    error InvalidParams();
    /// @notice Thrown when total number of votes does not exceed the minimum threshold of participation
    error InvalidParticipationThreshold();
    /// @notice Thrown when attempting to reuse a nullifier
    error InvalidNullifier();
    error AlreadyVoted();
    error SignalVoteOnly();

    event ProposalCreated(uint256 indexed proposalID, ProposalOption[] options, ProposalSettings settings);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 proposalId => Proposal) public proposals;
    /// @dev Whether a nullifier hash has been used already. Used to guarantee an action is only performed once by a single person
    mapping(uint256 => bool) internal nullifierHashes;

    /// @dev The middleware hook contract which will route the governor calls to the module
    address internal immutable router;

    /// @dev The address of the World ID Router contract that will be used for verifying proofs
    IWorldID internal immutable worldId;

    /// @dev The appId for the World IDkit
    string internal appId;

    /// @dev The World ID group ID (1 for Orb-verified)
    uint256 internal immutable groupId = 1;

    /// @dev Records the votes for approval voting criteria
    mapping(uint256 proposalId => mapping(address account => EnumerableSet.UintSet votes)) private accountVotesSet;

    uint256 internal constant MIN_PARTICIPATION = 2;

    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using SafeCast for uint256;
    using ByteHasher for bytes;
    using EnumerableSet for EnumerableSet.UintSet;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address payable _governor, address _router, IWorldID _worldId, string memory _appId)
        BaseHook(_governor)
    {
        worldId = _worldId;
        router = _router;
        appId = _appId;
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
            beforeVote: false,
            afterVote: true,
            beforePropose: false,
            afterPropose: true,
            beforeCancel: false,
            afterCancel: false,
            beforeQueue: true,
            afterQueue: false,
            beforeExecute: false,
            afterExecute: false
        });
    }

    /// @notice Reverts if the sender of the hook is not the governor
    function _onlyGovernor(address sender) internal view {
        if (sender != address(governor)) revert NotGovernor();
    }

    /// @notice Reverts if the msg.sender is not the middleware contract or designated router
    modifier _onlyRouter() {
        if (msg.sender != router) revert NotRouter();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 HOOKS
    //////////////////////////////////////////////////////////////*/

    function afterPropose(
        address sender,
        uint256 proposalId,
        address[] memory, /* targets */
        uint256[] memory, /* values */
        bytes[] memory, /* calldatas */
        string memory description
    ) external virtual override _onlyRouter returns (bytes4) {
        _onlyGovernor(sender);

        if (proposals[proposalId].governor != address(0)) {
            revert ExistingProposal();
        }

        bytes memory proposalData = bytes(description);
        (ProposalOption[] memory proposalOptions, ProposalSettings memory proposalSettings) =
            abi.decode(proposalData, (ProposalOption[], ProposalSettings));

        if (proposalSettings.minParticipation <= MIN_PARTICIPATION) revert InvalidParticipationThreshold();

        uint256 optionsLength = proposalOptions.length;

        if (proposalSettings.criteria != uint8(PassingCriteria.Standard)) {
            if (optionsLength == 0 || optionsLength > type(uint8).max) {
                revert InvalidParams();
            }
            if (proposalSettings.criteria == uint8(PassingCriteria.TopChoices)) {
                if (proposalSettings.criteriaValue > optionsLength) {
                    revert MaxChoicesExceeded();
                }
            }

            unchecked {
                ProposalOption memory option;
                for (uint256 i; i < optionsLength; ++i) {
                    option = proposalOptions[i];
                    proposals[proposalId].options.push(option);
                }
            }
        }

        proposals[proposalId].governor = sender;
        proposals[proposalId].settings = proposalSettings;
        proposals[proposalId].optionVotes = new uint128[](optionsLength);
        proposals[proposalId].externalNullifierHash =
            abi.encodePacked(abi.encodePacked(appId).hashToField(), proposalSettings.actionId).hashToField();

        emit ProposalCreated(proposalId, proposalOptions, proposalSettings);

        return (BaseHook.afterPropose.selector);
    }

    /**
     * Count votes by `account`. Votes can only be cast once.
     *
     * @param proposalId The id of the proposal.
     * @param account The account to count votes for.
     * @param support The type of vote to count.
     * @param weight The total vote weight of the `account`. Will be changed to 1 for orb-verified users
     * @param reason The string representing the reason for the vote direction.
     * @param params The WorldID IDKit parameters encoded as `(uint256, uint256, uint256[8], uint256[])` it contains the proof data and voting options for approval.
     */
    function afterVote(
        address sender,
        uint256 weight,
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) external override _onlyRouter returns (bytes4) {
        _onlyGovernor(sender);

        (uint256 root, uint256 nullifierHash, uint256[8] memory proof, uint256[] memory options) =
            _decodeVoteParams(params);
        uint256 totalOptions = options.length;
        // Verify WorldID proof with IDKit parameters
        _verifyProof(account, proposalId, support, root, nullifierHash, proof);

        Proposal memory proposal = proposals[proposalId];
        // One person, one Vote
        weight = 1;

        // Approval Voting check for a valid ballot
        if (proposal.settings.criteria != uint8(PassingCriteria.Standard)) {
            if (support == uint8(VoteType.For)) {
                if (totalOptions == 0) revert InvalidParams();
            }
        }

        _recordVote(
            proposalId, account, weight.toUint128(), support, options, totalOptions, proposal.settings.maxApprovals
        );

        return (this.afterVote.selector);
    }

    /**
     * @dev Return true if it satisfies the passing criteria uisng the participation threshold.
     * Used by governor in `_voteSucceeded`. See {Governor-_voteSucceeded}.
     *
     * @param proposalId The id of the proposal.
     */
    function beforeVoteSucceeded(address sender, uint256 proposalId)
        external
        view
        override
        returns (bytes4, bool, bool)
    {
        _onlyGovernor(sender);
        bool succeeded = false;
        Proposal memory proposal = proposals[proposalId];
        ProposalOption[] memory options = proposal.options;
        uint256 n = options.length;

        // Standard Voting (1P1V)
        if (proposal.settings.criteria == uint8(PassingCriteria.Standard)) {
            uint256 totalVotes = proposals[proposalId].againstVotes + proposals[proposalId].forVotes;
            if (totalVotes < proposals[proposalId].settings.minParticipation) {
                return (this.beforeVoteSucceeded.selector, true, false);
            }

            succeeded = (proposals[proposalId].againstVotes < proposals[proposalId].forVotes);
        }

        // Approval Voting
        unchecked {
            if (proposal.settings.criteria == uint8(PassingCriteria.Threshold)) {
                for (uint256 i; i < n; ++i) {
                    succeeded = (proposal.optionVotes[i] >= proposal.settings.criteriaValue);
                }
            } else if (proposal.settings.criteria == uint8(PassingCriteria.TopChoices)) {
                for (uint256 i; i < n; ++i) {
                    succeeded = (proposal.optionVotes[i] != 0);
                }
            }
        }

        return (this.beforeVoteSucceeded.selector, true, succeeded);
    }

    /**
     * @dev This function will revert if it is a signal vote otherwise queue the execution from the governor
     */
    function beforeQueue(
        address sender,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external virtual override returns (bytes4, address[] memory, uint256[] memory, bytes[] memory, bytes32) {
        _onlyGovernor(sender);

        uint256 proposalId = governor.hashProposal(targets, values, calldatas, descriptionHash);

        if (proposals[proposalId].settings.isSignalVote) {
            revert SignalVoteOnly();
        }

        return (this.beforeQueue.selector, targets, values, calldatas, descriptionHash);
    }

    /**
     * See IGovernor{propose}
     * @dev Creates the calldata for clients to interact with the governor
     * @param description The description string provided by the user.
     * @param proposalData The abi.encode bytes of the data to be appened at the end of the `description` i.e. `foo#proposalData=`.
     */
    function generateProposeCalldata(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        bytes memory proposalData
    ) external pure returns (bytes memory) {
        string memory descriptionWithData = string.concat(description, string(proposalData));
        return abi.encodeWithSelector(IGovernor.propose.selector, targets, values, calldatas, descriptionWithData);
    }

    /**
     * Defines the encoding for the expected `proposalSettings` in `propose`.
     * Encoding: `(ProposalOption, ProposalSettings)`
     *
     * @dev Can be used by clients to interact with modules programmatically without prior knowledge
     * on expected types.
     */
    function PROPOSAL_DATA_ENCODING() external pure virtual returns (string memory) {
        return
        "((string description)[] proposalOptions,(uint256 minParticipation, uint8 maxApprovals, uint8 criteria, uint128 criteriaValue, bool isSignalVote, string actionId) proposalSettings)";
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     *
     * - `support=bravo`: Supports vote options 0 = Against, 1 = For, 2 = Abstain, as in `GovernorBravo`.
     * - `quorum=for,abstain`: Against, For votes are counted towards tally; total number of votes must exceed `minParticipation`.
     * - `params=worldIDVoting`: params needs to be formatted as `VOTE_PARAMS_ENCODING`.
     */
    function COUNTING_MODE() public pure virtual returns (string memory) {
        return "support=bravo&quorum=against,for&params=worldIDVoting";
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

    function _recordVote(
        uint256 proposalId,
        address account,
        uint128 weight,
        uint8 support,
        uint256[] memory options,
        uint256 totalOptions,
        uint256 maxApprovals
    ) internal {
        // Record Approval votes
        if (totalOptions != 0) {
            uint256 option;
            uint256 prevOption;
            for (uint256 i; i < totalOptions;) {
                option = options[i];

                accountVotesSet[proposalId][account].add(option);

                // Revert if `option` is not strictly ascending
                if (i != 0) {
                    if (option <= prevOption) revert OptionsNotStrictlyAscending();
                }

                prevOption = option;

                /// @dev Revert if `option` is out of bounds
                proposals[proposalId].optionVotes[option] += weight;

                unchecked {
                    ++i;
                }
            }

            if (accountVotesSet[proposalId][account].length() > maxApprovals) {
                revert MaxApprovalsExceeded();
            }
        } else {
            // Record Standard Votes
            if (support == uint8(VoteType.For)) {
                proposals[proposalId].forVotes += weight;
            }

            if (support == uint8(VoteType.Against)) {
                proposals[proposalId].againstVotes += weight;
            }
        }
    }

    /// @param signal Arbitrary input from the user that cannot be tampered with. In this case, it is the user's wallet address.
    /// @param proposalId The id of the proposal.
    /// @param root The root (returned by the IDKit widget).
    /// @param nullifierHash The nullifier hash for this proof, preventing double signaling (returned by the IDKit widget).
    /// @param proof The zero-knowledge proof that demonstrates the claimer is registered with World ID (returned by the IDKit widget).
    function _verifyProof(
        address signal,
        uint256 proposalId,
        uint8 support,
        uint256 root,
        uint256 nullifierHash,
        uint256[8] memory proof
    ) internal {
        // First, we make sure this person hasn't done this before
        if (nullifierHashes[nullifierHash]) revert InvalidNullifier();

        // We now verify the provided proof is valid and the user is verified by World ID
        // Make signal unique proposalId + address
        worldId.verifyProof(
            root,
            groupId,
            abi.encodePacked(signal, proposalId, support).hashToField(),
            nullifierHash,
            proposals[proposalId].externalNullifierHash,
            proof
        );
        // Use groupID in verifyProof if Orb verified on a relevant testnet, for now just accept any WorldID

        // We now record the user has done this, so they can't do it again (sybil-resistance)
        nullifierHashes[nullifierHash] = true;
    }

    // Virtual method used to decode _countVote params that contain the proof information from IDKit .
    function _decodeVoteParams(bytes memory params)
        internal
        virtual
        returns (uint256 root, uint256 nullifierHash, uint256[8] memory proof, uint256[] memory options)
    {
        (root, nullifierHash, proof, options) = abi.decode(params, (uint256, uint256, uint256[8], uint256[]));
    }
}

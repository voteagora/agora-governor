// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Hooks} from "src/libraries/Hooks.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";
import {IMiddleware} from "src/interfaces/IMiddleware.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";

enum VoteType {
    Against,
    For,
    Abstain
}

struct ProposalSettings {
    uint248 againstThreshold;
    bool isRelativeToVotableSupply;
}

struct Proposal {
    address governor;
    ProposalSettings settings;
}

/// @custom:security-contact security@voteagora.com
contract OptimisticModule is BaseHook {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error WrongProposalId();
    error NotOptimisticProposalType();
    error ExistingProposal();
    error InvalidParams();

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    uint16 public constant PERCENT_DIVISOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 proposalId => Proposal) public proposals;
    IMiddleware public middleware;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address payable _governor, address _middleware) BaseHook(_governor) {
        middleware = IMiddleware(_middleware);
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
            afterVote: false,
            beforePropose: false,
            afterPropose: true,
            beforeCancel: false,
            afterCancel: false,
            beforeQueue: false,
            afterQueue: false,
            beforeExecute: true,
            afterExecute: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function afterPropose(
        address sender,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external virtual override returns (bytes4) {
        // _onlyGovernor(); TODO: only governor
        if (proposals[proposalId].governor != address(0)) {
            revert ExistingProposal();
        }

        // TODO: decode description into proposal data
        bytes memory proposalData = abi.encode(description);

        ProposalSettings memory proposalSettings = abi.decode(proposalData, (ProposalSettings));

        // uint8 proposalTypeId = IAgoraGovernor(msg.sender).getProposalType(
        //     proposalId
        // );
        uint8 proposalTypeId = 0;
        IMiddleware.ProposalType memory proposalType = middleware.proposalTypes(proposalTypeId);

        if (proposalType.quorum != 0 || proposalType.approvalThreshold != 0) {
            revert NotOptimisticProposalType();
        }
        if (
            proposalSettings.againstThreshold == 0
                || (proposalSettings.isRelativeToVotableSupply && proposalSettings.againstThreshold > PERCENT_DIVISOR)
        ) {
            revert InvalidParams();
        }

        proposals[proposalId].governor = msg.sender;
        proposals[proposalId].settings = proposalSettings;
    }

    /**
     * Format executeParams for a governor, given `proposalId` and `proposalData`.
     * Returns empty `targets`, `values` and `calldatas`.
     */
    function beforeExecute(address, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        pure
        override
        returns (bytes4, uint256)
    {
        // TODO: revert or return empty txs
        revert("Not implemented");
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Return true if `againstVotes` is lower than `againstThreshold`.
     * Used by governor in `_voteSucceeded`. See {Governor-_voteSucceeded}.
     *
     * @param proposalId The id of the proposal.
     */
    function beforeVoteSucceeded(address, uint256 proposalId) external view override returns (bytes4, bool) {
        // _onlyGovernor(); TODO: only governor
        Proposal memory proposal = proposals[proposalId];
        (uint256 againstVotes,,) = governor.proposalVotes(proposalId);

        uint256 againstThreshold = proposal.settings.againstThreshold;
        if (proposal.settings.isRelativeToVotableSupply) {
            uint256 snapshotBlock = governor.proposalSnapshot(proposalId);
            IERC5805 token = governor.token();
            againstThreshold = (token.getPastTotalSupply(snapshotBlock) * againstThreshold) / PERCENT_DIVISOR;
        }

        return (this.beforeVoteSucceeded.selector, againstVotes < againstThreshold);
    }

    /**
     * Defines the encoding for the expected `proposalData` in `propose`.
     * Encoding: `(ProposalSettings)`
     *
     * @dev Can be used by clients to interact with modules programmatically without prior knowledge
     * on expected types.
     */
    function PROPOSAL_DATA_ENCODING() external pure virtual returns (string memory) {
        return "((uint248 againstThreshold,bool isRelativeToVotableSupply) proposalSettings)";
    }

    /**
     * Defines the encoding for the expected `params` in `_countVote`.
     *
     * @dev Can be used by clients to interact with modules programmatically without prior knowledge
     * on expected types.
     */
    function VOTE_PARAMS_ENCODING() external pure virtual returns (string memory) {
        return "";
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     *
     * - `support=bravo`: Supports vote options 0 = Against, 1 = For, 2 = Abstain, as in `GovernorBravo`.
     * - `quorum=for,abstain`: Against, For and Abstain votes are counted towards quorum.
     */
    function COUNTING_MODE() public pure virtual returns (string memory) {
        return "support=bravo&quorum=against,for,abstain";
    }
}

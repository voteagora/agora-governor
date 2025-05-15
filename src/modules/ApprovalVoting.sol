// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Hooks} from "src/libraries/Hooks.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

enum VoteType {
    Against,
    For,
    Abstain
}

enum PassingCriteria {
    Threshold,
    TopChoices
}

struct ExecuteParams {
    address targets;
    uint256 values;
    bytes calldatas;
}

struct ProposalSettings {
    uint8 maxApprovals;
    uint8 criteria;
    address budgetToken;
    uint128 criteriaValue;
    uint128 budgetAmount;
}

struct ProposalOption {
    uint256 budgetTokensSpent;
    address[] targets;
    uint256[] values;
    bytes[] calldatas;
    string description;
}

struct Proposal {
    address governor;
    uint256 initBalance;
    uint128[] optionVotes;
    ProposalOption[] options;
    ProposalSettings settings;
}

/// @custom:security-contact security@voteagora.com
contract ApprovalVotingModule is BaseHook {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error MaxChoicesExceeded();
    error MaxApprovalsExceeded();
    error BudgetExceeded();
    error OptionsNotStrictlyAscending();
    error ExistingProposal();
    error InvalidParams();
    error NotGovernor();

    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 proposalId => Proposal) public proposals;
    mapping(uint256 proposalId => mapping(address account => EnumerableSet.UintSet votes)) private accountVotesSet;

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

    constructor(address payable _governor) BaseHook(_governor) {}

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

    /*//////////////////////////////////////////////////////////////
                                 HOOKS
    //////////////////////////////////////////////////////////////*/

    function afterPropose(
        address sender,
        uint256 proposalId,
        address[] memory, /*targets*/
        uint256[] memory, /*values*/
        bytes[] memory, /*calldatas*/
        string memory description
    ) external virtual override onlyGovernor(sender) returns (bytes4) {
        if (proposals[proposalId].governor != address(0)) {
            revert ExistingProposal();
        }

        bytes memory proposalData = bytes(description);

        (ProposalOption[] memory proposalOptions, ProposalSettings memory proposalSettings) =
            abi.decode(proposalData, (ProposalOption[], ProposalSettings));

        uint256 optionsLength = proposalOptions.length;
        if (optionsLength == 0 || optionsLength > type(uint8).max) {
            revert InvalidParams();
        }
        if (proposalSettings.criteria == uint8(PassingCriteria.TopChoices)) {
            if (proposalSettings.criteriaValue > optionsLength) {
                revert MaxChoicesExceeded();
            }
        }

        unchecked {
            // Ensure proposal params of each option have the same length between themselves
            ProposalOption memory option;
            for (uint256 i; i < optionsLength; ++i) {
                option = proposalOptions[i];
                if (option.targets.length != option.values.length || option.targets.length != option.calldatas.length) {
                    revert InvalidParams();
                }

                // Enforce that non-zero values use native budget token
                for (uint256 n = 0; n < option.targets.length; ++n) {
                    if (option.values[n] != 0 && proposalSettings.budgetToken != address(0)) {
                        revert InvalidParams();
                    }
                }

                proposals[proposalId].options.push(option);
            }
        }

        proposals[proposalId].governor = sender;
        proposals[proposalId].settings = proposalSettings;
        proposals[proposalId].optionVotes = new uint128[](optionsLength);

        return (this.afterPropose.selector);
    }

    /**
     * Count approvals voted by `account`. If voting for, options need to be set in ascending order. Votes can only be cast once.
     *
     * @param proposalId The id of the proposal.
     * @param account The account to count votes for.
     * @param support The type of vote to count.
     * @param weight The total vote weight of the `account`.
     * @param params The ids of the options to vote for sorted in ascending order, encoded as `uint256[]`.
     */
    function afterVote(
        address sender,
        uint256 weight,
        uint256 proposalId,
        address account,
        uint8 support,
        string memory, /*reason*/
        bytes memory params
    ) external override onlyGovernor(sender) returns (bytes4) {
        Proposal memory proposal = proposals[proposalId];

        if (support == uint8(VoteType.For)) {
            if (weight != 0) {
                uint256[] memory options = _decodeVoteParams(params);
                uint256 totalOptions = options.length;
                if (totalOptions == 0) {
                    revert InvalidParams();
                }

                if (totalOptions > proposals[proposalId].optionVotes.length) {
                    revert InvalidParams();
                }

                _recordVote(
                    proposalId, account, weight.toUint128(), options, totalOptions, proposal.settings.maxApprovals
                );
            }
        }

        return (this.afterVote.selector);
    }

    function beforeQueue(
        address sender,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        external
        override
        onlyGovernor(sender)
        returns (bytes4, address[] memory, uint256[] memory, bytes[] memory, bytes32)
    {
        uint256 proposalId = governor.hashProposal(targets, values, calldatas, descriptionHash);
        // Note: we assume that the beforeExecute will modify the calldata in the same way it is queued. This is to
        // ensure that the state is correctly reflected in the timelock
        (targets, values, calldatas) = formatExecuteParams(proposalId);
        return (this.beforeQueue.selector, targets, values, calldatas, descriptionHash);
    }

    /**
     * Format executeParams for a governor, given `proposalId` and `proposalData`.
     *
     * @param proposalId The id of the proposal.
     * @return targets The targets of the proposal.
     * @return values The values of the proposal.
     * @return calldatas The calldatas of the proposal.
     */
    function formatExecuteParams(uint256 proposalId)
        public
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        ProposalOption[] memory options = proposals[proposalId].options;
        ProposalSettings memory settings = proposals[proposalId].settings;

        {
            // If budgetToken is not ETH
            if (settings.budgetToken != address(0)) {
                // Save initBalance to be used as comparison in `checkBudget`
                proposals[proposalId].initBalance = IERC20(settings.budgetToken).balanceOf(governor.timelock());
            }
        }

        (uint128[] memory sortedOptionVotes, ProposalOption[] memory sortedOptions) =
            _sortOptions(proposals[proposalId].optionVotes, options);

        (uint256 executeParamsLength, uint256 succeededOptionsLength) =
            _countOptions(sortedOptions, sortedOptionVotes, settings);

        ExecuteParams[] memory executeParams = new ExecuteParams[](executeParamsLength);
        executeParamsLength = 0;
        uint256 totalValue;

        {
            uint256 n;
            ProposalOption memory option;
            bool budgetExceeded = false;

            // Flatten `options` by filling `executeParams` until budgetAmount is exceeded
            for (uint256 i; i < succeededOptionsLength; ++i) {
                option = sortedOptions[i];

                for (n = 0; n < option.targets.length; n++) {
                    // If `budgetToken` is ETH and value is not zero, add transaction value to `totalValue`
                    if (settings.budgetToken == address(0) && option.values[n] != 0) {
                        if (totalValue + option.values[n] > settings.budgetAmount) {
                            budgetExceeded = true;
                            break; // break inner loop
                        } else {
                            // Add to total value only if the new total vaue would be below budget
                            totalValue += option.values[n];
                        }
                    }

                    executeParams[executeParamsLength + n] =
                        ExecuteParams(option.targets[n], option.values[n], option.calldatas[n]);
                }

                // If `budgetAmount` for ETH is exceeded, skip option.
                if (budgetExceeded) break;

                // Check if budgetAmount is exceeded for non-ETH tokens
                if (settings.budgetToken != address(0) && settings.budgetAmount != 0) {
                    if (option.budgetTokensSpent != 0) {
                        if (totalValue + option.budgetTokensSpent > settings.budgetAmount) break; // break outer loop for non-ETH tokens
                        totalValue += option.budgetTokensSpent;
                    }
                }

                executeParamsLength += n;
            }
        }

        unchecked {
            // Increase by one to account for additional `checkBudget` call
            uint256 effectiveParamsLength = executeParamsLength + 1;

            // Init params lengths
            targets = new address[](effectiveParamsLength);
            values = new uint256[](effectiveParamsLength);
            calldatas = new bytes[](effectiveParamsLength);
        }

        // Set n `targets`, `values` and `calldatas`
        for (uint256 i; i < executeParamsLength; ++i) {
            targets[i] = executeParams[i].targets;
            values[i] = executeParams[i].values;
            calldatas[i] = executeParams[i].calldatas;
        }

        // Set `checkBudget` as last call
        targets[executeParamsLength] = address(this);
        values[executeParamsLength] = 0;
        calldatas[executeParamsLength] = abi.encodeCall(this.checkBudget, (proposalId, totalValue));
    }

    /**
     * Hook called by a governor after execute, for `proposalId` with `proposalData`.
     * Revert if the transaction has resulted in more tokens being spent than `budgetAmount`.
     *
     * @param proposalId The id of the proposal.
     * @param budgetTokensSpent The total amount of tokens that can be spent.
     */
    function checkBudget(uint256 proposalId, uint256 budgetTokensSpent) public view {
        ProposalSettings memory settings = proposals[proposalId].settings;

        if (settings.budgetToken != address(0) && settings.budgetAmount > 0) {
            uint256 initBalance = proposals[proposalId].initBalance;
            uint256 finalBalance = IERC20(settings.budgetToken).balanceOf(governor.timelock());

            // If `finalBalance` is higher than `initBalance`, ignore the budget check
            if (finalBalance < initBalance) {
                /// @dev Cannot underflow as `finalBalance` is less than `initBalance`
                unchecked {
                    if (initBalance - finalBalance > budgetTokensSpent) {
                        revert BudgetExceeded();
                    }
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Return the ids of the options voted by `account` on `proposalId`.
     */
    function getAccountVotes(uint256 proposalId, address account) external view returns (uint256[] memory) {
        return accountVotesSet[proposalId][account].values();
    }

    /**
     * Return the total number of votes cast by `account` on `proposalId`.
     */
    function getAccountTotalVotes(uint256 proposalId, address account) external view returns (uint256) {
        return accountVotesSet[proposalId][account].length();
    }

    /**
     * @dev Return true if at least one option satisfies the passing criteria.
     * Used by governor in `_voteSucceeded`. See {Governor-_voteSucceeded}.
     *
     * @param proposalId The id of the proposal.
     */
    function beforeVoteSucceeded(address sender, uint256 proposalId)
        external
        view
        override
        onlyGovernor(sender)
        returns (bytes4, bool)
    {
        Proposal memory proposal = proposals[proposalId];

        ProposalOption[] memory options = proposal.options;
        uint256 n = options.length;
        unchecked {
            if (proposal.settings.criteria == uint8(PassingCriteria.Threshold)) {
                for (uint256 i; i < n; ++i) {
                    if (proposal.optionVotes[i] >= proposal.settings.criteriaValue) {
                        return (this.beforeVoteSucceeded.selector, true);
                    }
                }
            } else if (proposal.settings.criteria == uint8(PassingCriteria.TopChoices)) {
                for (uint256 i; i < n; ++i) {
                    if (proposal.optionVotes[i] != 0) {
                        return (this.beforeVoteSucceeded.selector, true);
                    }
                }
            }
        }

        return (this.beforeVoteSucceeded.selector, false);
    }

    /**
     * Defines the encoding for the expected `proposalData` in `propose`.
     * Encoding: `(ProposalOption[], ProposalSettings)`
     *
     * @dev Can be used by clients to interact with modules programmatically without prior knowledge
     * on expected types.
     */
    function PROPOSAL_DATA_ENCODING() external pure virtual returns (string memory) {
        return
        "((uint256 budgetTokensSpent,address[] targets,uint256[] values,bytes[] calldatas,string description)[] proposalOptions,(uint8 maxApprovals,uint8 criteria,address budgetToken,uint128 criteriaValue,uint128 budgetAmount) proposalSettings)";
    }

    /**
     * Defines the encoding for the expected `params` in `_countVote`.
     * Encoding: `uint256[]`
     *
     * @dev Can be used by clients to interact with modules programmatically without prior knowledge
     * on expected types.
     */
    function VOTE_PARAMS_ENCODING() external pure virtual returns (string memory) {
        return "uint256[] optionIds";
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     *
     * - `support=bravo`: Supports vote options 0 = Against, 1 = For, 2 = Abstain, as in `GovernorBravo`.
     * - `quorum=for,abstain`: Against, For and Abstain votes are counted towards quorum.
     * - `params=approvalVote`: params needs to be formatted as `VOTE_PARAMS_ENCODING`.
     */
    function COUNTING_MODE() public pure virtual returns (string memory) {
        return "support=bravo&quorum=against,for,abstain&params=approvalVote";
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
        uint256[] memory options,
        uint256 totalOptions,
        uint256 maxApprovals
    ) internal {
        uint256 option;
        uint256 prevOption;
        for (uint256 i; i < totalOptions; ++i) {
            option = options[i];

            accountVotesSet[proposalId][account].add(option);

            // Revert if `option` is not strictly ascending
            if (i != 0) {
                if (option <= prevOption) revert OptionsNotStrictlyAscending();
            }

            prevOption = option;

            /// @dev Revert if `option` is out of bounds
            proposals[proposalId].optionVotes[option] += weight;
        }

        if (accountVotesSet[proposalId][account].length() > maxApprovals) {
            revert MaxApprovalsExceeded();
        }
    }

    // Sort `options` by `optionVotes` in descending order
    function _sortOptions(uint128[] memory optionVotes, ProposalOption[] memory options)
        internal
        pure
        returns (uint128[] memory, ProposalOption[] memory)
    {
        unchecked {
            uint128 highestValue;
            ProposalOption memory highestOption;
            uint256 index;

            for (uint256 i; i < optionVotes.length - 1; ++i) {
                highestValue = optionVotes[i];

                for (uint256 j = i + 1; j < optionVotes.length; ++j) {
                    if (optionVotes[j] > highestValue) {
                        highestValue = optionVotes[j];
                        index = j;
                    }
                }

                if (index != 0) {
                    optionVotes[index] = optionVotes[i];
                    optionVotes[i] = highestValue;

                    highestOption = options[index];
                    options[index] = options[i];
                    options[i] = highestOption;

                    index = 0;
                }
            }

            return (optionVotes, options);
        }
    }

    // Derive `executeParamsLength` and `succeededOptionsLength` based on passing criteria
    function _countOptions(
        ProposalOption[] memory options,
        uint128[] memory optionVotes,
        ProposalSettings memory settings
    ) internal pure returns (uint256 executeParamsLength, uint256 succeededOptionsLength) {
        uint256 n = options.length;
        unchecked {
            uint256 i;
            if (settings.criteria == uint8(PassingCriteria.Threshold)) {
                // if criteria is `Threshold`, loop through options until `optionVotes` is less than threshold
                for (i; i < n; ++i) {
                    if (optionVotes[i] >= settings.criteriaValue) {
                        executeParamsLength += options[i].targets.length;
                    } else {
                        break;
                    }
                }
            } else if (settings.criteria == uint8(PassingCriteria.TopChoices)) {
                // if criteria is `TopChoices`, loop through options until the top choices are filled
                for (i; i < settings.criteriaValue; ++i) {
                    if (optionVotes[i] > 0) {
                        executeParamsLength += options[i].targets.length;
                    } else {
                        break;
                    }
                }
            }
            succeededOptionsLength = i;
        }
    }

    // Virtual method used to decode _countVote params.
    function _decodeVoteParams(bytes memory params) internal virtual returns (uint256[] memory options) {
        options = abi.decode(params, (uint256[]));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Hooks} from "src/libraries/Hooks.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";

// import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/// @custom:security-contact security@voteagora.com
contract VPAdapter is BaseHook {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotGovernor();

    // event ProposalCreated();

    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/


    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public admin;
    // mapping(uint256 proposalId => Proposal) public proposals;
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

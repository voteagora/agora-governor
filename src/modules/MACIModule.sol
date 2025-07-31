// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

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


struct Proposal {
    address governor;
    address maci;
    address poll;
    uint256 pollId;
}

/// @custom:security-contact security@voteagora.com
contract MACIModule is BaseHook {
    error NotGovernor();
    error InvalidMiddleware();

    IMiddleware public middleware;

    constructor(address payable _governor, address _middleware) BaseHook(_governor) {
        if (_middleware == address(0)) revert InvalidMiddleware();
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
            afterVoteSucceeded: true,
            beforeQuorumCalculation: true,
            afterQuorumCalculation: true,
            beforeVote: true,
            afterVote: true,
            beforePropose: true,
            afterPropose: false,
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
}


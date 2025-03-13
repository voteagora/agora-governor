// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgoraGovernor} from "src/AgoraGovernor.sol";
import {Hooks} from "src/libraries/Hooks.sol";
import {IHooks} from "src/interfaces/IHooks.sol";

/// @title Base Hook
/// @notice Base Hook contract
/// @custom:security-contact security@voteagora.com
/// Inspired by https://github.com/Uniswap/v4-periphery/blob/main/src/base/hooks/BaseHook.sol[Uniswap v4 implementation of hooks].
abstract contract BaseHook is IHooks {
    error InvalidGovernor();
    error HookNotImplemented();

    AgoraGovernor public immutable governor;

    constructor(address payable _governor) {
        if (_governor == address(0)) revert InvalidGovernor();

        governor = AgoraGovernor(_governor);
        validateHookAddress(this);
    }

    /// @notice Returns a struct of permissions to signal which hook functions are to be implemented
    /// @dev Used at deployment to validate the address correctly represents the expected permissions
    function getHookPermissions() public pure virtual returns (Hooks.Permissions memory);

    /// @notice Validates the deployed hook address agrees with the expected permissions of the hook
    /// @dev this function is virtual so that we can override it during testing,
    /// which allows us to deploy an implementation to any address
    /// and then etch the bytecode into the correct address
    function validateHookAddress(BaseHook _this) internal pure virtual {
        Hooks.validateHookPermissions(_this, getHookPermissions());
    }

    /// @inheritdoc IHooks
    function beforeInitialize(address) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function afterInitialize(address) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function beforeVoteSucceeded(address, uint256) external view virtual returns (bytes4, bool) {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function afterVoteSucceeded(address, uint256, bool) external view virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function beforeQuorumCalculation(address, uint256) external view virtual returns (bytes4, uint256) {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function afterQuorumCalculation(address, uint256, uint256) external view virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function beforeVote(address, uint256, address, uint8, string memory, bytes memory)
        external
        virtual
        returns (bytes4, uint256)
    {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function afterVote(address, uint256, uint256, address, uint8, string memory, bytes memory)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function beforePropose(address, address[] memory, uint256[] memory, bytes[] memory, string memory)
        external
        virtual
        returns (bytes4, uint256)
    {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function afterPropose(address, uint256, address[] memory, uint256[] memory, bytes[] memory, string memory)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function beforeCancel(address, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        returns (bytes4, uint256)
    {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function afterCancel(address, uint256, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function beforeQueue(address, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        returns (bytes4, bytes memory)
    {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function afterQueue(address, uint256, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function beforeExecute(address, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        returns (bytes4, bytes memory)
    {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function afterExecute(address, uint256, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }
}

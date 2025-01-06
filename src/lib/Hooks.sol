// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IHooks} from "../interfaces/IHooks.sol";

/// Inspired in the https://github.com/Uniswap/v4-core/blob/main/src/libraries/Hooks.sol[Uniswap v4 implementation of hooks].
library Hooks {
    using Hooks for IHooks;

    uint160 internal constant ALL_HOOK_MASK = uint160((1 << 12) - 1);

    uint160 internal constant BEFORE_INITIALIZE_FLAG = 1 << 11;
    uint160 internal constant AFTER_INITIALIZE_FLAG = 1 << 10;

    uint160 internal constant BEFORE_QUORUM_CALCULATION_FLAG = 1 << 9;
    uint160 internal constant AFTER_QUORUM_CALCULATION_FLAG = 1 << 8;

    uint160 internal constant BEFORE_VOTE_FLAG = 1 << 7;
    uint160 internal constant AFTER_VOTE_FLAG = 1 << 6;

    uint160 internal constant BEFORE_PROPOSE_FLAG = 1 << 5;
    uint160 internal constant AFTER_PROPOSE_FLAG = 1 << 4;

    uint160 internal constant BEFORE_CANCEL_FLAG = 1 << 3;
    uint160 internal constant AFTER_CANCEL_FLAG = 1 << 2;

    uint160 internal constant BEFORE_EXECUTE_FLAG = 1 << 1;
    uint160 internal constant AFTER_EXECUTE_FLAG = 1 << 0;

    struct Permissions {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeQuorumCalculation;
        bool afterQuorumCalculation;
        bool beforeVote;
        bool afterVote;
        bool beforePropose;
        bool afterPropose;
        bool beforeCancel;
        bool afterCancel;
        bool beforeExecute;
        bool afterExecute;
    }

    /// @notice Thrown if the address will not lead to the specified hook calls being called
    /// @param hooks The address of the hooks contract
    error HookAddressNotValid(address hooks);

    /// @notice Hook did not return its selector
    error InvalidHookResponse();

    /// @notice Additional context for ERC-7751 wrapped error when a hook call fails
    error HookCallFailed();

    /// @notice Utility function intended to be used in hook constructors to ensure
    /// the deployed hooks address causes the intended hooks to be called
    /// @param permissions The hooks that are intended to be called
    /// @dev permissions param is memory as the function will be called from constructors
    function validateHookPermissions(IHooks self, Permissions memory permissions) internal pure {
        if (
            permissions.beforeInitialize != self.hasPermission(BEFORE_INITIALIZE_FLAG)
                || permissions.afterInitialize != self.hasPermission(AFTER_INITIALIZE_FLAG)
                || permissions.beforeQuorumCalculation != self.hasPermission(BEFORE_QUORUM_CALCULATION_FLAG)
                || permissions.afterQuorumCalculation != self.hasPermission(AFTER_QUORUM_CALCULATION_FLAG)
                || permissions.beforeVote != self.hasPermission(BEFORE_VOTE_FLAG)
                || permissions.afterVote != self.hasPermission(AFTER_VOTE_FLAG)
                || permissions.beforePropose != self.hasPermission(BEFORE_PROPOSE_FLAG)
                || permissions.afterPropose != self.hasPermission(AFTER_PROPOSE_FLAG)
                || permissions.beforeCancel != self.hasPermission(BEFORE_CANCEL_FLAG)
                || permissions.afterCancel != self.hasPermission(AFTER_CANCEL_FLAG)
                || permissions.beforeExecute != self.hasPermission(BEFORE_EXECUTE_FLAG)
                || permissions.afterExecute != self.hasPermission(AFTER_EXECUTE_FLAG)
        ) {
            revert HookAddressNotValid(address(self));
        }
    }

    /// @notice Ensures that the hook address includes at least one hook flag, or is the 0 address
    /// @param self The hook to verify
    /// @return bool True if the hook address is valid
    function isValidHookAddress(IHooks self) internal pure returns (bool) {
        // If a hook contract is set, it must have at least 1 flag set
        return address(self) == address(0) ? true : (uint160(address(self)) & ALL_HOOK_MASK > 0);
    }

    function parseSelector(bytes memory result) internal pure returns (bytes4 selector) {
        // equivalent: (selector,) = abi.decode(result, (bytes4, int256));
        assembly ("memory-safe") {
            selector := mload(add(result, 0x20))
        }
    }

    /// @notice performs a hook call using the given calldata on the given hook that doesn't return a response
    /// @return result The complete data returned by the hook
    function callHook(IHooks self, bytes memory data) internal returns (bytes memory result) {
        bool success;
        assembly ("memory-safe") {
            success := call(gas(), self, 0, add(data, 0x20), mload(data), 0, 0)
        }
        if (!success) revert HookCallFailed();

        // The call was successful, fetch the returned data
        assembly ("memory-safe") {
            // allocate result byte array from the free memory pointer
            result := mload(0x40)
            // store new free memory pointer at the end of the array padded to 32 bytes
            mstore(0x40, add(result, and(add(returndatasize(), 0x3f), not(0x1f))))
            // store length in memory
            mstore(result, returndatasize())
            // copy return data to result
            returndatacopy(add(result, 0x20), 0, returndatasize())
        }

        // Length must be at least 32 to contain the selector. Check expected selector and returned selector match.
        if (result.length < 32 || parseSelector(result) != parseSelector(data)) {
            revert InvalidHookResponse();
        }
    }

    /// @notice performs a hook static call using the given calldata on the given hook that doesn't return a response
    /// @return result The complete data returned by the hook
    function staticCallHook(IHooks self, bytes memory data) internal view returns (bytes memory result) {
        bool success;
        assembly ("memory-safe") {
            success := staticcall(gas(), self, add(data, 0x20), mload(data), 0, 0)
        }
        if (!success) revert HookCallFailed();

        // The call was successful, fetch the returned data
        assembly ("memory-safe") {
            // allocate result byte array from the free memory pointer
            result := mload(0x40)
            // store new free memory pointer at the end of the array padded to 32 bytes
            mstore(0x40, add(result, and(add(returndatasize(), 0x3f), not(0x1f))))
            // store length in memory
            mstore(result, returndatasize())
            // copy return data to result
            returndatacopy(add(result, 0x20), 0, returndatasize())
        }

        // Length must be at least 32 to contain the selector. Check expected selector and returned selector match.
        if (result.length < 32 || parseSelector(result) != parseSelector(data)) {
            revert InvalidHookResponse();
        }
    }

    /// @notice modifier to prevent calling a hook if they initiated the action
    modifier noSelfCall(IHooks self) {
        if (msg.sender != address(self)) {
            _;
        }
    }

    /// @notice calls beforeInitialize hook if permissioned and validates return value
    function beforeInitialize(IHooks self) internal noSelfCall(self) {
        if (self.hasPermission(BEFORE_INITIALIZE_FLAG)) {
            self.callHook(abi.encodeCall(IHooks.beforeInitialize, (msg.sender)));
        }
    }

    /// @notice calls afterInitialize hook if permissioned and validates return value
    function afterInitialize(IHooks self) internal noSelfCall(self) {
        if (self.hasPermission(AFTER_INITIALIZE_FLAG)) {
            self.callHook(abi.encodeCall(IHooks.afterInitialize, (msg.sender)));
        }
    }

    /// @notice calls beforeQuorumCalculation hook if permissioned and validates return value
    function beforeQuorumCalculation(IHooks self) internal view noSelfCall(self) {
        if (self.hasPermission(BEFORE_QUORUM_CALCULATION_FLAG)) {
            self.staticCallHook(abi.encodeCall(IHooks.beforeQuorumCalculation, (msg.sender)));
        }
    }

    /// @notice calls afterQuorumCalculation hook if permissioned and validates return value
    function afterQuorumCalculation(IHooks self) internal view noSelfCall(self) {
        if (self.hasPermission(AFTER_QUORUM_CALCULATION_FLAG)) {
            self.staticCallHook(abi.encodeCall(IHooks.afterQuorumCalculation, (msg.sender)));
        }
    }

    /// @notice calls beforeVote hook if permissioned and validates return value
    function beforeVote(IHooks self) internal noSelfCall(self) {
        if (self.hasPermission(BEFORE_VOTE_FLAG)) {
            self.callHook(abi.encodeCall(IHooks.beforeVote, (msg.sender)));
        }
    }

    /// @notice calls afterVote hook if permissioned and validates return value
    function afterVote(IHooks self) internal noSelfCall(self) {
        if (self.hasPermission(AFTER_VOTE_FLAG)) {
            self.callHook(abi.encodeCall(IHooks.afterVote, (msg.sender)));
        }
    }

    /// @notice calls beforePropose hook if permissioned and validates return value
    function beforePropose(IHooks self) internal noSelfCall(self) {
        if (self.hasPermission(BEFORE_PROPOSE_FLAG)) {
            self.callHook(abi.encodeCall(IHooks.beforePropose, (msg.sender)));
        }
    }

    /// @notice calls afterPropose hook if permissioned and validates return value
    function afterPropose(IHooks self) internal noSelfCall(self) {
        if (self.hasPermission(AFTER_PROPOSE_FLAG)) {
            self.callHook(abi.encodeCall(IHooks.afterPropose, (msg.sender)));
        }
    }

    /// @notice calls beforeCancel hook if permissioned and validates return value
    function beforeCancel(IHooks self) internal noSelfCall(self) {
        if (self.hasPermission(BEFORE_CANCEL_FLAG)) {
            self.callHook(abi.encodeCall(IHooks.beforeCancel, (msg.sender)));
        }
    }

    /// @notice calls afterCancel hook if permissioned and validates return value
    function afterCancel(IHooks self) internal noSelfCall(self) {
        if (self.hasPermission(AFTER_CANCEL_FLAG)) {
            self.callHook(abi.encodeCall(IHooks.afterCancel, (msg.sender)));
        }
    }

    /// @notice calls beforeExecute hook if permissioned and validates return value
    function beforeExecute(IHooks self) internal noSelfCall(self) {
        if (self.hasPermission(BEFORE_EXECUTE_FLAG)) {
            self.callHook(abi.encodeCall(IHooks.beforeExecute, (msg.sender)));
        }
    }

    /// @notice calls afterExecute hook if permissioned and validates return value
    function afterExecute(IHooks self) internal noSelfCall(self) {
        if (self.hasPermission(AFTER_EXECUTE_FLAG)) {
            self.callHook(abi.encodeCall(IHooks.afterExecute, (msg.sender)));
        }
    }

    function hasPermission(IHooks self, uint160 flag) internal pure returns (bool) {
        return uint160(address(self)) & flag != 0;
    }
}

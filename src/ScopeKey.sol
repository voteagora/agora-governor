// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library ScopeKey {
    /**
     * @notice Generates the scope key defined as the contract address combined with the function selector
     * @param contractAddress Address of the contract to be enforced by the scope
     * @param selector A byte4 function selector on the contract to be enforced by the scope
     */
    function _pack(address contractAddress, bytes4 selector) external pure returns (bytes24 result) {
        bytes20 left = bytes20(contractAddress);
        assembly ("memory-safe") {
            left := and(left, shl(96, not(0)))
            selector := and(selector, shl(224, not(0)))
            result := or(left, shr(160, selector))
        }
    }

    /**
     * @notice Unpacks the scope key into the constituent parts, i.e. contract address the first 20 bytes and the function selector as the last 4 bytes
     * @param self A byte24 key to be unpacked representing the key for a defined scope
     */
    function _unpack(bytes24 self) external pure returns (address, bytes4) {
        bytes20 contractAddress;
        bytes4 selector;

        assembly ("memory-safe") {
            contractAddress := and(shl(mul(8, 0), self), shl(96, not(0)))
        }

        assembly ("memory-safe") {
            selector := and(shl(mul(8, 20), self), shl(224, not(0)))
        }

        return (address(contractAddress), selector);
    }
}

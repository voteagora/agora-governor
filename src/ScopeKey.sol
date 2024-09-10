// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library ScopeKey {
    error OutOfRangeAccess();

    function extract_24_20(bytes24 self, uint8 offset) internal pure returns (bytes20 result) {
        if (offset > 4) revert OutOfRangeAccess();
        assembly ("memory-safe") {
            result := and(shl(mul(8, offset), self), shl(96, not(0)))
        }
    }

    function pack_20_4(bytes20 left, bytes4 right) internal pure returns (bytes24 result) {
        assembly ("memory-safe") {
            left := and(left, shl(96, not(0)))
            right := and(right, shl(224, not(0)))
            result := or(left, shr(160, right))
        }
    }

    function extract_24_4(bytes24 self, uint8 offset) internal pure returns (bytes4 result) {
        if (offset > 20) revert OutOfRangeAccess();
        assembly ("memory-safe") {
            result := and(shl(mul(8, offset), self), shl(224, not(0)))
        }
    }

    /**
     * @notice Generates the scope key defined as the contract address combined with the function selector
     * @param contractAddress Address of the contract to be enforced by the scope
     * @param selector A byte4 function selector on the contract to be enforced by the scope
     */
    function _pack(address contractAddress, bytes4 selector) external pure returns (bytes24) {
        return pack_20_4(bytes20(contractAddress), selector);
    }

    /**
     * @notice Unpacks the scope key into the constituent parts, i.e. contract address the first 20 bytes and the function selector as the last 4 bytes
     * @param self A byte24 key to be unpacked representing the key for a defined scope
     */
    function _unpack(bytes24 self) external pure returns (address, bytes4) {
        return (address(extract_24_20(self, 0)), extract_24_4(self, 20));
    }
}

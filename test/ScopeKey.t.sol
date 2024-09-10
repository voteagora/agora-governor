// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

contract ScopePackerTest is Test {
    address contractAddress = makeAddr("contractAddress");
    bytes proposedTx =
        abi.encodeWithSignature("transfer(address,address,uint256)", address(0), address(0), uint256(100));
    bytes4 selector;

    function setUp() public virtual {
        selector = bytes4(proposedTx);
    }

    /**
     * @notice Generates the scope key defined as the contract address combined with the function selector
     * @param contractAddress Address of the contract to be enforced by the scope
     * @param selector A byte4 function selector on the contract to be enforced by the scope
     */
    function _pack(address contractAddress, bytes4 selector) internal pure returns (bytes24 result) {
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
    function _unpack(bytes24 self) internal pure returns (address, bytes4) {
        bytes20 contractAddress;
        bytes4 selector;

        assembly ("memory-safe") {
            contractAddress := and(shl(mul(8, 0), self), shl(96, not(0)))
            selector := and(shl(mul(8, 20), self), shl(224, not(0)))
        }

        return (address(contractAddress), selector);
    }

    function test_ScopeKeyPacking() public virtual {
        bytes24 key = _pack(contractAddress, selector);
        (address _contract, bytes4 _selector) = _unpack(key);
        assertEq(contractAddress, _contract);
        assertEq(selector, _selector);
    }
}

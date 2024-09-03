// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Packing} from "@openzeppelin/contracts/utils/Packing.sol";

library ScopeKey {
    /**
     * @notice Generates the scope key defined as the contract address combined with the function selector
     * @param contractAddress Address of the contract to be enforced by the scope
     * @param selector A byte4 function selector on the contract to be enforced by the scope
     */
    function _pack(address contractAddress, bytes4 selector) external pure returns (bytes24) {
        return Packing.pack_20_4(bytes20(contractAddress), selector);
    }

    /**
     * @notice Unpacks the scope key into the constituent parts, i.e. contract address the first 20 bytes and the function selector as the last 4 bytes
     * @param self A byte24 key to be unpacked representing the key for a defined scope
     */
    function _unpack(bytes24 self) external pure returns (address, bytes4) {
        return (
            address(Packing.extract_24_20(self, 0)),
            Packing.extract_24_4(self, 20)
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibString} from "@solady/utils/LibString.sol";
import {JSONParserLib} from "@solady/utils/JSONParserLib.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library Parser {
    using LibString for string;
    using JSONParserLib for string;
    using SafeCast for uint256;

    error DescriptionTooShort();
    error InvalidDescription();
    error InvalidMarker();

    /// @dev Returns the string inside the marker, which must be in the format `#marker=???`
    function _parseMarker(string memory description, string memory marker)
        internal
        pure
        returns (string memory value)
    {
        unchecked {
            // Check the format of the marker
            if (!marker.startsWith("#") || !marker.contains("=")) revert InvalidMarker();

            // Length is too short to contain the marker
            if (bytes(description).length <= bytes(marker).length) revert DescriptionTooShort();

            // Slice the description after the marker
            string[] memory parts = description.split(marker);
            if (parts.length != 2) revert InvalidDescription();

            // Slice the marker part if there's any other marker after the given marker
            value = parts[1].split("#")[0];
        }
    }

    /// @dev Returns the proposal type id specified in the description, which must be in the format `#proposalTypeId=???`
    /// at the end of the description or before the next parameter/marker if it exists.
    ///
    /// If the description does not include this pattern, this function will revert. This includes:
    /// - If the `???` part is not a valid number.
    /// - If the `???` part is a valid number but exceeds the maximum value of `uint8`.
    function _parseProposalTypeId(string memory description) internal pure returns (uint8 proposalTypeId) {
        unchecked {
            string memory value = _parseMarker(description, "#proposalTypeId=");

            // Cast and return the proposal type id
            return value.parseUint().toUint8();
        }
    }

    /// @dev Returns the proposal data specified in the description, which must be in the format `#proposalData=???`
    /// at the end of the description or before the next parameter/marker if it exists.
    ///
    /// If the description does not include this pattern, this function will revert
    function _parseProposalData(string memory description) internal pure returns (bytes memory proposalData) {
        unchecked {
            string memory value = _parseMarker(description, "#proposalData=");

            // Cast and return the proposal data
            return bytes(value);
        }
    }
}

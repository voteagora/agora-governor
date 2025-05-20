// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Hooks} from "src/libraries/Hooks.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Packing} from "@openzeppelin/contracts/utils/Packing.sol";

/// @custom:security-contact security@voteagora.com
contract MultiTokenModule is BaseHook {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidWeight();
    error InvalidResponse();
    error InvalidSelector();
    error InvalidToken();
    error TokenAlreadyExists();
    error TokenDoesNotExist();
    error NotGovernor();
    error NotGovernance();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokenAdded(address indexed token, uint64 weight, bytes4 selector);
    event TokenRemoved(address indexed token);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Set of tokens that are supported by the module
    EnumerableSet.Bytes32Set private tokens;

    /// @notice The divisor for the weights
    uint16 public constant PERCENT_DIVISOR = 10_000;

    /// @notice Reverts if the sender of the hook is not the governor
    modifier _onlyGovernance(address sender) {
        _;
        if (sender != governor.timelock()) revert NotGovernance();
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address payable _governor) BaseHook(_governor) {}

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice The hook called before a vote is cast
    function beforeVote(address sender, uint256 proposalId, address account, uint8, string memory, bytes memory)
        external
        override
        returns (bytes4, bool, uint256)
    {
        if (msg.sender != address(governor)) revert NotGovernor();

        // Get the proposal snapshot
        uint256 proposalSnapshot = governor.proposalSnapshot(proposalId);

        // Store weight (voting power)
        uint256 totalWeight = 0;

        // Get the values in the set and iterate over them
        uint256 length = tokens.length();
        for (uint256 i = 0; i < length; i++) {
            // Get the value at the current index
            bytes32 value = tokens.at(i);

            // Extract the token address, selector, and weight
            address token = address(Packing.extract_32_20(value, 0));
            bytes4 selector = bytes4(Packing.extract_32_4(value, 20));

            // Call the token's selector with the account and proposalId as arguments
            (bool success, bytes memory result) =
                token.staticcall(abi.encodeWithSelector(selector, account, proposalSnapshot));
            if (!success) revert InvalidResponse();

            // Apply weight to voting power and add to total
            uint256 weight = abi.decode(result, (uint256)) * uint64(Packing.extract_32_8(value, 24)) / PERCENT_DIVISOR;
            totalWeight += weight;
        }

        return (this.beforeVote.selector, true, totalWeight);
    }

    /// @notice Add a token to the module
    /// @param token The address of the token to add
    /// @param weight The weight of the token
    /// @param selector The selector of the function to call, which must take (address,uint256) as arguments and return a uint256
    function addToken(address token, uint64 weight, bytes4 selector) external _onlyGovernance(msg.sender) {
        if (token == address(0)) revert InvalidToken();
        if (weight == 0 || weight > PERCENT_DIVISOR) revert InvalidWeight();
        if (selector == bytes4(0)) revert InvalidSelector();
        if (_tokenExists(token)) revert TokenAlreadyExists();

        // Check that selector can be called on token
        (bool success, bytes memory result) = token.staticcall(abi.encodeWithSelector(selector, address(0), 0));
        if (!success || result.length != 32) revert InvalidSelector();

        bytes12 subpack = Packing.pack_4_8(selector, bytes8(weight));
        bytes32 pack = Packing.pack_20_12(bytes20(token), subpack);

        tokens.add(pack);

        emit TokenAdded(token, weight, selector);
    }

    /// @notice Remove a token from the module
    /// @param token The address of the token to remove
    function removeToken(address token) external _onlyGovernance(msg.sender) {
        uint256 index = _findIndex(token);
        tokens.remove(tokens.at(index));

        emit TokenRemoved(token);
    }

    /// @notice Gets the weight of a token
    /// @param token The address of the token to get the weight of
    /// @return weight The weight of the token
    function getTokenWeight(address token) external view returns (uint64 weight) {
        bytes32 value = tokens.at(_findIndex(token));
        return uint64(Packing.extract_32_8(value, 24));
    }

    /// @notice Gets the selector of a token
    /// @param token The address of the token to get the selector of
    /// @return selector The selector of the token
    function getTokenSelector(address token) external view returns (bytes4 selector) {
        bytes32 value = tokens.at(_findIndex(token));
        return bytes4(Packing.extract_32_4(value, 20));
    }

    /// @notice Gets the token address at a given index
    /// @param index The index of the token to get the address of
    /// @return token The address of the token
    function getTokenAddress(uint256 index) external view returns (address token) {
        if (index >= tokens.length()) revert TokenDoesNotExist();

        bytes32 value = tokens.at(index);
        return address(Packing.extract_32_20(value, 0));
    }

    /*//////////////////////////////////////////////////////////////
                             PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeVoteSucceeded: false,
            afterVoteSucceeded: false,
            beforeQuorumCalculation: false,
            afterQuorumCalculation: false,
            beforeVote: true,
            afterVote: false,
            beforePropose: false,
            afterPropose: false,
            beforeCancel: false,
            afterCancel: false,
            beforeQueue: false,
            afterQueue: false,
            beforeExecute: false,
            afterExecute: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                             PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Finds the index of a token in the set
    /// @param token The address of the token to find the index of
    /// @return index The index of the token
    function _findIndex(address token) internal view returns (uint256) {
        // Get the values in the set and iterate over them
        uint256 length = tokens.length();
        for (uint256 i = 0; i < length; i++) {
            // Get the value at the current index
            bytes32 value = tokens.at(i);

            // Extract the token address, selector, and weight
            address _token = address(Packing.extract_32_20(value, 0));

            if (token == _token) return i;
        }

        revert TokenDoesNotExist();
    }

    /// @notice Check if a token exists in the set
    /// @param token The address of the token to check
    /// @return exists True if the token exists, false otherwise
    function _tokenExists(address token) internal view returns (bool) {
        // Get the values in the set and iterate over them
        uint256 length = tokens.length();
        for (uint256 i = 0; i < length; i++) {
            // Get the value at the current index
            bytes32 value = tokens.at(i);

            // Extract the token address, selector, and weight
            address _token = address(Packing.extract_32_20(value, 0));

            if (token == _token) return true;
        }

        return false;
    }
}

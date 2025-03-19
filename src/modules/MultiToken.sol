// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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
    error InvalidSelector();
    error InvalidToken();
    error TokenAlreadyExists();
    error TokenDoesNotExist();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Set of tokens that are supported by the module
    EnumerableSet.Bytes32Set private tokens;

    /// @notice Mapping of tokens to index in the set
    mapping(address token => uint256 index) private tokenIndexes;

    /// @notice The divisor for the weights
    uint16 public constant PERCENT_DIVISOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address payable _governor) BaseHook(_governor) {}

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice The hook called before a vote is cast
    function beforeVote(
        address sender,
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) external override returns (bytes4, uint256) {
        // Get the values in the set and iterate over them
        uint256 length = tokens.length();
        for (uint256 i = 0; i < length; i++) {
            // Get the value at the current index
            bytes32 value = tokens.at(i);

            // Extract the token address, selector, and weight
            address token = address(Packing.extract_32_20(value, 0));
            bytes4 selector = bytes4(Packing.extract_32_4(value, 20));
            uint64 weight = uint64(Packing.extract_32_8(value, 24));
        }

        return (this.beforeVote.selector, 0);
    }

    /// @notice Add a token to the module
    /// @param token The address of the token to add
    /// @param weight The weight of the token
    /// @param selector The selector of the function to call, which must take (address,uint256) as arguments and return a uint256
    function addToken(address token, uint64 weight, bytes4 selector) external {
        if (token == address(0)) revert InvalidToken();
        if (weight == 0) revert InvalidWeight();
        if (selector == bytes4(0)) revert InvalidSelector();
        if (tokenIndexes[token] != 0) revert TokenAlreadyExists();

        bytes12 subpack = Packing.pack_4_8(selector, bytes8(weight));
        bytes32 pack = Packing.pack_20_12(bytes20(token), subpack);

        tokens.add(pack);
        tokenIndexes[token] = tokens.length();
    }

    /// @notice Remove a token from the module
    /// @param token The address of the token to remove
    function removeToken(address token) external {
        if (tokenIndexes[token] == 0) revert TokenDoesNotExist();

        uint256 index = tokenIndexes[token];
        tokens.remove(tokens.at(index));
        delete tokenIndexes[token];
    }

    /// @notice Gets the weight of a token
    /// @param token The address of the token to get the weight of
    /// @return weight The weight of the token
    function getTokenWeight(address token) external view returns (uint64 weight) {
        if (tokenIndexes[token] == 0) revert TokenDoesNotExist();

        bytes32 value = tokens.at(tokenIndexes[token]);
        return uint64(Packing.extract_32_8(value, 24));
    }

    /// @notice Gets the selector of a token
    /// @param token The address of the token to get the selector of
    /// @return selector The selector of the token
    function getTokenSelector(address token) external view returns (bytes4 selector) {
        if (tokenIndexes[token] == 0) revert TokenDoesNotExist();

        bytes32 value = tokens.at(tokenIndexes[token]);
        return bytes4(Packing.extract_32_4(value, 20));
    }

    /// @notice Gets the token address at a given index
    /// @param index The index of the token to get the address of
    /// @return token The address of the token
    function getTokenAddress(uint256 index) external view returns (address token) {
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
}

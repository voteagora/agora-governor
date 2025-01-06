// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Hooks} from "src/libraries/Hooks.sol";
import {IHooks} from "src/interfaces/IHooks.sol";

contract MockHooks is IHooks {
    using Hooks for IHooks;

    bytes public beforeInitializeData;
    bytes public afterInitializeData;
    bytes public beforeQuorumCalculationData;
    bytes public afterQuorumCalculationData;
    bytes public beforeVoteData;
    bytes public afterVoteData;
    bytes public beforeProposeData;
    bytes public afterProposeData;
    bytes public beforeCancelData;
    bytes public afterCancelData;
    bytes public beforeExecuteData;
    bytes public afterExecuteData;

    mapping(bytes4 => bytes4) public returnValues;

    function beforeInitialize(address) external override returns (bytes4) {
        beforeInitializeData = new bytes(123);
        bytes4 selector = MockHooks.beforeInitialize.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterInitialize(address) external override returns (bytes4) {
        afterInitializeData = new bytes(123);
        bytes4 selector = MockHooks.afterInitialize.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeQuorumCalculation(address, uint256) external view override returns (bytes4, uint256) {
        bytes4 selector = MockHooks.beforeQuorumCalculation.selector;
        return (returnValues[selector] == bytes4(0) ? selector : returnValues[selector], 0);
    }

    function afterQuorumCalculation(address, uint256) external view override returns (bytes4, uint256) {
        bytes4 selector = MockHooks.afterQuorumCalculation.selector;
        return (returnValues[selector] == bytes4(0) ? selector : returnValues[selector], 0);
    }

    function beforeVote(address, uint256, address, uint8, string memory, bytes memory params)
        external
        override
        returns (bytes4, uint256)
    {
        beforeVoteData = params;
        bytes4 selector = MockHooks.beforeVote.selector;
        return (returnValues[selector] == bytes4(0) ? selector : returnValues[selector], 0);
    }

    function afterVote(address, uint256, uint256, address, uint8, string memory, bytes memory params)
        external
        override
        returns (bytes4, uint256)
    {
        afterVoteData = params;
        bytes4 selector = MockHooks.afterVote.selector;
        return (returnValues[selector] == bytes4(0) ? selector : returnValues[selector], 0);
    }

    function beforePropose(address, address[] memory, uint256[] memory, bytes[] memory, string memory)
        external
        override
        returns (bytes4, uint256)
    {
        // beforeProposeData = hookData;
        bytes4 selector = MockHooks.beforePropose.selector;
        return (returnValues[selector] == bytes4(0) ? selector : returnValues[selector], 0);
    }

    function afterPropose(address, uint256, address[] memory, uint256[] memory, bytes[] memory, string memory)
        external
        override
        returns (bytes4, uint256)
    {
        // afterProposeData = hookData;
        bytes4 selector = MockHooks.afterPropose.selector;
        return (returnValues[selector] == bytes4(0) ? selector : returnValues[selector], 0);
    }

    function beforeCancel(address, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        override
        returns (bytes4, uint256)
    {
        // beforeCancelData = hookData;
        bytes4 selector = MockHooks.beforeCancel.selector;
        return (returnValues[selector] == bytes4(0) ? selector : returnValues[selector], 0);
    }

    function afterCancel(address, uint256, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        override
        returns (bytes4, uint256)
    {
        // afterCancelData = hookData;
        bytes4 selector = MockHooks.afterCancel.selector;
        return (returnValues[selector] == bytes4(0) ? selector : returnValues[selector], 0);
    }

    function beforeExecute(address, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        override
        returns (bytes4, uint256)
    {
        // beforeExecuteData = hookData;
        bytes4 selector = MockHooks.beforeExecute.selector;
        return (returnValues[selector] == bytes4(0) ? selector : returnValues[selector], 0);
    }

    function afterExecute(address, uint256, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        override
        returns (bytes4, uint256)
    {
        // afterExecuteData = hookData;
        bytes4 selector = MockHooks.afterExecute.selector;
        return (returnValues[selector] == bytes4(0) ? selector : returnValues[selector], 0);
    }

    function setReturnValue(bytes4 key, bytes4 value) external {
        returnValues[key] = value;
    }
}

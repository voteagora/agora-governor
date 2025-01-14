// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "src/BaseHook.sol";
import {Hooks} from "src/libraries/Hooks.sol";
import {AgoraGovernor} from "src/AgoraGovernor.sol";

contract BaseHookMock is BaseHook {
    event BeforeInitialize();
    event AfterInitialize();
    event BeforeQuorumCalculation();
    event AfterQuorumCalculation();
    event BeforeVote();
    event AfterVote();
    event BeforePropose();
    event AfterPropose();
    event BeforeCancel();
    event AfterCancel();
    event BeforeQueue();
    event AfterQueue();
    event BeforeExecute();
    event AfterExecute();

    constructor(address payable _governor) BaseHook(_governor) {}

    function beforeInitialize(address) external virtual override returns (bytes4) {
        emit BeforeInitialize();
        return this.beforeInitialize.selector;
    }

    function afterInitialize(address) external virtual override returns (bytes4) {
        emit AfterInitialize();
        return this.afterInitialize.selector;
    }

    function beforeQuorumCalculation(address, uint256 beforeQuorum)
        external
        virtual
        override
        returns (bytes4, uint256)
    {
        emit BeforeQuorumCalculation();
        return (this.beforeQuorumCalculation.selector, beforeQuorum);
    }

    function afterQuorumCalculation(address, uint256 afterQuorum) external virtual override returns (bytes4, uint256) {
        emit AfterQuorumCalculation();
        return (this.afterQuorumCalculation.selector, afterQuorum);
    }

    function beforeVote(address, uint256, address, uint8, string memory, bytes memory)
        external
        virtual
        override
        returns (bytes4, uint256)
    {
        emit BeforeVote();
        return (this.beforeVote.selector, 0);
    }

    function afterVote(address, uint256, uint256, address, uint8, string memory, bytes memory)
        external
        virtual
        override
        returns (bytes4, uint256)
    {
        emit AfterVote();
        return (this.afterVote.selector, 0);
    }

    function beforePropose(address, address[] memory, uint256[] memory, bytes[] memory, string memory)
        external
        virtual
        override
        returns (bytes4, uint256)
    {
        emit BeforePropose();
        return (this.beforePropose.selector, 0);
    }

    function afterPropose(address, uint256, address[] memory, uint256[] memory, bytes[] memory, string memory)
        external
        virtual
        override
        returns (bytes4, uint256)
    {
        emit AfterPropose();
        return (this.afterPropose.selector, 0);
    }

    function beforeCancel(address, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        override
        returns (bytes4, uint256)
    {
        emit BeforeCancel();
        return (this.beforeCancel.selector, 0);
    }

    function afterCancel(address, uint256, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        override
        returns (bytes4, uint256)
    {
        emit AfterCancel();
        return (this.afterCancel.selector, 0);
    }

    function beforeQueue(address, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        override
        returns (bytes4, uint256)
    {
        emit BeforeQueue();
        return (this.beforeQueue.selector, 0);
    }

    function afterQueue(address, uint256, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        override
        returns (bytes4, uint256)
    {
        emit AfterQueue();
        return (this.afterQueue.selector, 0);
    }

    function beforeExecute(address, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        override
        returns (bytes4, uint256)
    {
        emit BeforeExecute();
        return (this.beforeExecute.selector, 0);
    }

    function afterExecute(address, uint256, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        override
        returns (bytes4, uint256)
    {
        emit AfterExecute();
        return (this.afterExecute.selector, 0);
    }

    /**
     * @dev Set all permissions.
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeQuorumCalculation: true,
            afterQuorumCalculation: true,
            beforeVote: true,
            afterVote: true,
            beforePropose: true,
            afterPropose: true,
            beforeCancel: true,
            afterCancel: true,
            beforeQueue: true,
            afterQueue: true,
            beforeExecute: true,
            afterExecute: true
        });
    }
}

contract BaseHookMockReverts is BaseHook {
    constructor(address payable _governor) BaseHook(_governor) {}

    /**
     * @dev Set all permissions.
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeQuorumCalculation: true,
            afterQuorumCalculation: true,
            beforeVote: true,
            afterVote: true,
            beforePropose: true,
            afterPropose: true,
            beforeCancel: true,
            afterCancel: true,
            beforeQueue: true,
            afterQueue: true,
            beforeExecute: true,
            afterExecute: true
        });
    }

    // Exclude from coverage report
    function test() public {}
}

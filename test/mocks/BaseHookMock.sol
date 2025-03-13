// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "src/hooks/BaseHook.sol";
import {Hooks} from "src/libraries/Hooks.sol";
import {AgoraGovernor} from "src/AgoraGovernor.sol";

contract BaseHookMock is BaseHook {
    event BeforeInitialize();
    event AfterInitialize();
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

    function beforeVoteSucceeded(address, uint256) external view virtual override returns (bytes4, bool) {
        return (this.beforeVoteSucceeded.selector, true);
    }

    function afterVoteSucceeded(address, uint256, bool) external view virtual override returns (bytes4) {
        return (this.afterVoteSucceeded.selector);
    }

    function beforeQuorumCalculation(address, uint256) external view virtual override returns (bytes4, uint256) {
        return (this.beforeQuorumCalculation.selector, 100);
    }

    function afterQuorumCalculation(address, uint256, uint256) external view virtual override returns (bytes4) {
        return (this.afterQuorumCalculation.selector);
    }

    function beforeVote(address, uint256, address, uint8 support, string memory, bytes memory)
        external
        virtual
        override
        returns (bytes4, uint256)
    {
        emit BeforeVote();
        return (this.beforeVote.selector, uint256(support));
    }

    function afterVote(address, uint256, uint256, address, uint8, string memory, bytes memory)
        external
        virtual
        override
        returns (bytes4)
    {
        emit AfterVote();
        return (this.afterVote.selector);
    }

    function beforePropose(
        address,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external virtual override returns (bytes4, uint256) {
        emit BeforePropose();
        uint256 proposalId = governor.hashProposal(targets, values, calldatas, keccak256(abi.encodePacked(description)));

        return (this.beforePropose.selector, proposalId);
    }

    function afterPropose(address, uint256, address[] memory, uint256[] memory, bytes[] memory, string memory)
        external
        virtual
        override
        returns (bytes4)
    {
        emit AfterPropose();
        return (this.afterPropose.selector);
    }

    function beforeCancel(
        address,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external virtual override returns (bytes4, uint256) {
        emit BeforeCancel();
        uint256 proposalId = governor.hashProposal(targets, values, calldatas, descriptionHash);
        return (this.beforeCancel.selector, proposalId);
    }

    function afterCancel(address, uint256, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        override
        returns (bytes4)
    {
        emit AfterCancel();
        return (this.afterCancel.selector);
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
        returns (bytes4)
    {
        emit AfterQueue();
        return (this.afterQueue.selector);
    }

    function beforeExecute(
        address,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external virtual override returns (bytes4, uint256) {
        emit BeforeExecute();
        uint256 proposalId = governor.hashProposal(targets, values, calldatas, descriptionHash);
        return (this.beforeExecute.selector, proposalId);
    }

    function afterExecute(address, uint256, address[] memory, uint256[] memory, bytes[] memory, bytes32)
        external
        virtual
        override
        returns (bytes4)
    {
        emit AfterExecute();
        return (this.afterExecute.selector);
    }

    /**
     * @dev Set all permissions.
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeVoteSucceeded: true,
            afterVoteSucceeded: true,
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
            beforeVoteSucceeded: true,
            afterVoteSucceeded: true,
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

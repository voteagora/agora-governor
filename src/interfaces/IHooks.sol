// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice AgoraGovernor decides whether to invoke specific hooks by inspecting the least significant bits
/// @dev Should only be callable by the AgoraGovernor contract instance.
/// Inspired in the https://github.com/Uniswap/v4-core/blob/main/src/interfaces/IHooks.sol[Uniswap v4 implementation of hooks].
interface IHooks {
    /// @notice The hook called before the state of a governor is initialized
    function beforeInitialize(address sender) external returns (bytes4);

    /// @notice The hook called after the state of a governor is initialized
    function afterInitialize(address sender) external returns (bytes4);

    /// @notice The hook called before quorum calculation is performed
    function beforeQuorumCalculation(address sender, uint256 proposalId) external returns (bytes4, uint256);

    /// @notice The hook called after quorum calculation is performed
    function afterQuorumCalculation(address sender, uint256 proposalId, uint256 quorum)
        external
        returns (bytes4, uint256);

    /// @notice The hook called before a vote is cast
    function beforeVote(
        address sender,
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) external returns (bytes4, uint256);

    /// @notice The hook called after a vote is cast
    function afterVote(
        address sender,
        uint256 weight,
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) external returns (bytes4, uint256);

    /// @notice The hook called before a proposal is created
    function beforePropose(
        address sender,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (bytes4, uint256);

    /// @notice The hook called after a proposal is created
    function afterPropose(
        address sender,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (bytes4, uint256);

    /// @notice The hook called before a proposal is canceled
    function beforeCancel(
        address sender,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (bytes4, uint256);

    /// @notice The hook called after a proposal is canceled
    function afterCancel(
        address sender,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (bytes4, uint256);

    /// @notice The hook called before a proposal is queued
    function beforeQueue(
        address sender,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (bytes4, uint256);

    /// @notice The hook called after a proposal is queued
    function afterQueue(
        address sender,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (bytes4, uint256);

    /// @notice The hook called before a proposal is executed
    function beforeExecute(
        address sender,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (bytes4, uint256);

    /// @notice The hook called after a proposal is executed
    function afterExecute(
        address sender,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (bytes4, uint256);
}

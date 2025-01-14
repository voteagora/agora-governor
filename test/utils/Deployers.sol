// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {IHooks} from "src/interfaces/IHooks.sol";
import {AgoraGovernor} from "src/AgoraGovernor.sol";
import {AgoraGovernorMock} from "test/mocks/AgoraGovernorMock.sol";

import {MockToken} from "test/mocks/MockToken.sol";

contract Deployers is Test {
    // Contracts
    AgoraGovernorMock public governor;
    TimelockController public timelock;
    MockToken public token;

    // Addresses
    address deployer = makeAddr("deployer");
    address admin = makeAddr("admin");
    address proxyAdmin = makeAddr("proxyAdmin");
    address manager = makeAddr("manager");
    address minter = makeAddr("minter");

    // Variables
    uint256 timelockDelay = 2 days;
    uint48 votingDelay = 1;
    uint32 votingPeriod = 14;
    uint256 proposalThreshold = 1;
    uint256 quorumNumerator = 3000;

    // Calculate governor address
    address governorAddress = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 2);

    function deployGovernor(address hook) internal virtual {
        vm.startPrank(deployer);

        // Deploy token
        token = new MockToken(minter);

        // Deploy timelock
        address[] memory proposers = new address[](1);
        proposers[0] = governorAddress;
        address[] memory executors = new address[](1);
        executors[0] = governorAddress;
        timelock = new TimelockController(timelockDelay, proposers, executors, deployer);

        // Deploy governor
        governor = new AgoraGovernorMock(
            votingDelay, votingPeriod, proposalThreshold, quorumNumerator, token, timelock, admin, manager, IHooks(hook)
        );

        vm.stopPrank();
    }
}

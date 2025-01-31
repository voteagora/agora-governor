// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Hooks} from "src/libraries/Hooks.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {MockHooks} from "test/mocks/MockHooks.sol";
import {AgoraGovernorMock} from "test/mocks/AgoraGovernorMock.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract HooksTest is Test {
    using Hooks for IHooks;

    MockHooks mockHooks;

    uint48 votingDelay = 1;
    uint32 votingPeriod = 14;
    uint256 proposalThreshold = 1;
    uint256 quorumNumerator = 3000;

    function setUp() public {
        MockHooks impl = new MockHooks();
        vm.etch(address(uint160(Hooks.ALL_HOOK_MASK)), address(impl).code);
        mockHooks = MockHooks(address(uint160(Hooks.ALL_HOOK_MASK)));
    }

    function deployGovernor(address hook) public returns (AgoraGovernorMock governor) {
        governor = new AgoraGovernorMock(
            votingDelay,
            votingPeriod,
            proposalThreshold,
            quorumNumerator,
            IVotes(address(this)),
            TimelockController(payable(address(this))),
            address(this),
            address(this),
            IHooks(address(hook))
        );
    }

    function test_initialize_succeedsWithHook() public {
        AgoraGovernorMock governor = deployGovernor(address(mockHooks));

        assertEq(governor.admin(), address(this));
        assertEq(mockHooks.beforeInitializeData(), new bytes(123));
        assertEq(mockHooks.afterInitializeData(), new bytes(123));
    }

    function test_beforeInitialize_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        deployGovernor(address(mockHooks));
    }

    function test_afterInitialize_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        deployGovernor(address(mockHooks));
    }
}

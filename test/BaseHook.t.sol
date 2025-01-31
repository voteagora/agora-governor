// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {BaseHook} from "src/BaseHook.sol";
import {BaseHookMock, BaseHookMockReverts} from "test/mocks/BaseHookMock.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {Hooks} from "src/libraries/Hooks.sol";

import {Deployers} from "test/utils/Deployers.sol";

contract BaseHookTest is Test, Deployers {
    BaseHookMock hook;
    BaseHookMockReverts hookReverts;

    function setUp() public {
        hook = BaseHookMock(address(uint160(Hooks.ALL_HOOK_MASK)));

        deployCodeTo("test/mocks/BaseHookMock.sol:BaseHookMock", abi.encode(governorAddress), address(hook));

        hookReverts = BaseHookMockReverts(address(0x100000000000000000000000000000000000ffFf));
        deployCodeTo(
            "test/mocks/BaseHookMock.sol:BaseHookMockReverts", abi.encode(governorAddress), address(hookReverts)
        );
    }

    function test_initialize_succeeds() public {
        vm.expectEmit(address(hook));
        emit BaseHookMock.BeforeInitialize();
        vm.expectEmit(address(hook));
        emit BaseHookMock.AfterInitialize();
        deployGovernor(address(hook));
    }

    function test_quorum_succeeds() public {
        deployGovernor(address(hook));

        vm.expectCall(
            address(hook), abi.encodeCall(hook.beforeQuorumCalculation, (0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, 0))
        );
        vm.expectCall(
            address(hook),
            abi.encodeCall(hook.afterQuorumCalculation, (0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, 0, 0))
        );
        governor.quorum(0);
    }

    function test_propose_succeeds() public {
        deployGovernor(address(hook));

        address _actor = makeAddr("actor");
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.test_initialize_succeeds.selector);

        vm.prank(admin);
        governor.setProposalThreshold(10);

        vm.prank(minter);
        token.mint(_actor, 100);
        vm.startPrank(_actor);
        token.delegate(_actor);
        vm.roll(block.number + 1);

        uint256 proposalId;
        vm.expectEmit(address(hook));
        emit BaseHookMock.BeforePropose();
        vm.expectEmit(address(hook));
        emit BaseHookMock.AfterPropose();
        proposalId = governor.propose(targets, values, calldatas, "Test");
        vm.stopPrank();
    }

    function test_vote_succeeds(address _actor) public {
        deployGovernor(address(hook));

        _actor = makeAddr("actor");

        vm.prank(minter);
        token.mint(_actor, 100);
        vm.startPrank(_actor);
        token.delegate(_actor);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.test_initialize_succeeds.selector);

        vm.startPrank(_actor);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 2);

        vm.expectEmit(address(hook));
        emit BaseHookMock.BeforeVote();
        vm.expectEmit(address(hook));
        emit BaseHookMock.AfterVote();
        governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));

        vm.roll(block.number + 14);
        vm.stopPrank();
    }

    function test_cancel_succeeds() public {
        deployGovernor(address(hook));

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.test_initialize_succeeds.selector);

        vm.startPrank(manager);
        governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 2);

        vm.expectEmit(address(hook));
        emit BaseHookMock.BeforeCancel();
        vm.expectEmit(address(hook));
        emit BaseHookMock.AfterCancel();
        governor.cancel(targets, values, calldatas, keccak256("Test"));

        vm.stopPrank();
    }

    function test_queue_succeeds(address _actor) public {
        deployGovernor(address(hook));

        _actor = makeAddr("actor");

        vm.prank(minter);
        token.mint(_actor, 100);
        vm.startPrank(_actor);
        token.delegate(_actor);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.test_initialize_succeeds.selector);

        vm.startPrank(_actor);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 2);

        governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));

        vm.roll(block.number + 14);

        vm.expectEmit(address(hook));
        emit BaseHookMock.BeforeQueue();
        vm.expectEmit(address(hook));
        emit BaseHookMock.AfterQueue();
        governor.queue(targets, values, calldatas, keccak256("Test"));
    }

    function test_execute_succeeds(address _actor, uint256 _elapsedAfterQueuing) public {
        deployGovernor(address(hook));

        _actor = makeAddr("actor");

        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);

        vm.prank(minter);
        token.mint(_actor, 100);
        vm.startPrank(_actor);
        token.delegate(_actor);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.test_initialize_succeeds.selector);

        vm.startPrank(_actor);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 2);

        governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));

        vm.roll(block.number + 14);

        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.expectEmit(address(hook));
        emit BaseHookMock.BeforeExecute();
        vm.expectCall(
            address(hook),
            abi.encodeCall(hook.afterExecute, (_actor, proposalId, targets, values, calldatas, keccak256("Test")))
        );

        governor.execute(targets, values, calldatas, keccak256("Test"));
    }
}

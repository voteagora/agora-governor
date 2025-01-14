// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {BaseHook} from "src/BaseHook.sol";
import {BaseHookMock, BaseHookMockReverts} from "test/mocks/BaseHookMock.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {Hooks} from "src/libraries/Hooks.sol";

import {Deployers} from "test/utils/Deployers.sol";

contract BaseHookTest is Test, Deployers {
    BaseHookMock hook;
    BaseHookMockReverts hookReverts;

    function setUp() public {
        hook = BaseHookMock(
            address(
                uint160(
                    Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_QUORUM_CALCULATION_FLAG
                        | Hooks.AFTER_QUORUM_CALCULATION_FLAG | Hooks.BEFORE_VOTE_FLAG | Hooks.AFTER_VOTE_FLAG
                        | Hooks.BEFORE_PROPOSE_FLAG | Hooks.AFTER_PROPOSE_FLAG | Hooks.BEFORE_CANCEL_FLAG
                        | Hooks.AFTER_CANCEL_FLAG | Hooks.BEFORE_QUEUE_FLAG | Hooks.AFTER_QUEUE_FLAG
                        | Hooks.BEFORE_EXECUTE_FLAG | Hooks.AFTER_EXECUTE_FLAG
                )
            )
        );

        deployCodeTo("test/mocks/BaseHookMock.sol:BaseHookMock", abi.encode(governorAddress), address(hook));

        hookReverts = BaseHookMockReverts(address(0x1000000000000000000000000000000000003ffF));
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

        vm.expectCall(address(hook), abi.encodeCall(hook.beforeQuorumCalculation, (0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, 0)));
        vm.expectCall(address(hook), abi.encodeCall(hook.afterQuorumCalculation, (0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, 0)));
        governor.quorum(0);
    }

    function test_propose_succeeds(address _actor) public {
        deployGovernor(address(hook));
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.test_initialize_succeeds.selector);

        vm.prank(admin);
        governor.setProposalThreshold(10);

        // Give actor enough tokens to meet proposal threshold.
        vm.prank(minter);
        token.mint(_actor, 100);
        vm.startPrank(_actor);
        token.delegate(_actor);
        vm.roll(block.number + 1);

        uint256 proposalId;
        vm.expectCall(address(hook), abi.encodeCall(
            hook.beforePropose, (0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, targets, values, calldatas, "Test"))
        );
        proposalId = governor.propose(targets, values, calldatas, "Test");
        vm.stopPrank();
    }
}

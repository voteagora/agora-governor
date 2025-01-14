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
                    Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG
                        | Hooks.BEFORE_QUORUM_CALCULATION_FLAG| Hooks.AFTER_QUORUM_CALCULATION_FLAG
                        | Hooks.BEFORE_VOTE_FLAG | Hooks.AFTER_VOTE_FLAG
                        | Hooks.BEFORE_PROPOSE_FLAG | Hooks.AFTER_PROPOSE_FLAG
                        | Hooks.BEFORE_CANCEL_FLAG | Hooks.AFTER_CANCEL_FLAG
                        | Hooks.BEFORE_QUEUE_FLAG | Hooks.AFTER_QUEUE_FLAG
                        | Hooks.BEFORE_EXECUTE_FLAG | Hooks.AFTER_EXECUTE_FLAG
                )
            )
        );

        deployCodeTo("test/mocks/BaseHookMock.sol:BaseHookMock", abi.encode(governorAddress), address(hook));

        hookReverts = BaseHookMockReverts(address(0x1000000000000000000000000000000000003ffF));
        deployCodeTo("test/mocks/BaseHookMock.sol:BaseHookMockReverts", abi.encode(governorAddress), address(hookReverts));
    }

    function test_initialize_succeeds() public {
        // Deploy governor
        vm.expectEmit(address(hook));
        emit BaseHookMock.BeforeInitialize();
        vm.expectEmit(address(hook));
        emit BaseHookMock.AfterInitialize();
        deployGovernor(address(hook));
    }
}

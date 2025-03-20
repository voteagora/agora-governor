// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {Hooks} from "src/libraries/Hooks.sol";
import {MultiTokenModule} from "src/modules/MultiToken.sol";

import {Deployers} from "test/utils/Deployers.sol";

contract MultiTokenModuleTest is Test, Deployers {
    MultiTokenModule module;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        deployGovernor(address(0));

        module = MultiTokenModule(address(uint160(Hooks.BEFORE_VOTE_FLAG)));
        deployCodeTo("src/modules/MultiToken.sol:MultiTokenModule", abi.encode(address(governor)), address(module));
    }

    function test_addToken() public {
        module.addToken(address(token), 100, bytes4(keccak256("getPastVotes(address,uint256)")));

        assertEq(module.getTokenWeight(address(token)), 100);
        assertEq(module.getTokenSelector(address(token)), bytes4(keccak256("getPastVotes(address,uint256)")));
        assertEq(module.getTokenAddress(0), address(token));
    }

    function test_removeToken() public {
        test_addToken();

        module.removeToken(address(token));

        vm.expectRevert(MultiTokenModule.TokenDoesNotExist.selector);
        module.getTokenWeight(address(token));

        vm.expectRevert(MultiTokenModule.TokenDoesNotExist.selector);
        module.getTokenSelector(address(token));

        vm.expectRevert();
        module.getTokenAddress(0);
    }

    function test_addAndRemoveMultiple() public {
        module.addToken(address(token), 5_000, bytes4(keccak256("transfer(address,uint256)")));
        module.addToken(address(0xbeef), 5_000, bytes4(keccak256("transfer(address,uint256)")));
        module.removeToken(address(token));

        assertEq(module.getTokenWeight(address(0xbeef)), 5_000);
        assertEq(module.getTokenSelector(address(0xbeef)), bytes4(keccak256("transfer(address,uint256)")));
        assertEq(module.getTokenAddress(0), address(0xbeef));
    }

    function test_addToken_reverts_alreadyExists() public {
        module.addToken(address(token), 100, bytes4(keccak256("transfer(address,uint256)")));

        vm.expectRevert(MultiTokenModule.TokenAlreadyExists.selector);
        module.addToken(address(token), 100, bytes4(keccak256("transfer(address,uint256)")));
    }

    function test_addToken_reverts_invalidToken() public {
        vm.expectRevert(MultiTokenModule.InvalidToken.selector);
        module.addToken(address(0), 100, bytes4(keccak256("transfer(address,uint256)")));
    }

    function test_addToken_reverts_invalidWeight() public {
        vm.expectRevert(MultiTokenModule.InvalidWeight.selector);
        module.addToken(address(token), 0, bytes4(keccak256("transfer(address,uint256)")));

        vm.expectRevert(MultiTokenModule.InvalidWeight.selector);
        module.addToken(address(token), 10_001, bytes4(keccak256("transfer(address,uint256)")));
    }

    function test_addToken_reverts_invalidSelector() public {
        vm.expectRevert(MultiTokenModule.InvalidSelector.selector);
        module.addToken(address(token), 100, bytes4(0));
    }
}

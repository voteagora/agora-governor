// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {Hooks} from "src/libraries/Hooks.sol";
import {MultiTokenModule} from "src/modules/MultiToken.sol";

import {MockToken} from "test/mocks/MockToken.sol";
import {Deployers} from "test/utils/Deployers.sol";

import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";

contract MultiTokenModuleTest is Test, Deployers {
    MultiTokenModule module;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        module = MultiTokenModule(address(uint160(Hooks.BEFORE_VOTE_FLAG)));
        deployGovernor(address(module));
        deployCodeTo("src/modules/MultiToken.sol:MultiTokenModule", abi.encode(address(governor)), address(module));
    }

    function test_addToken() public {
        module.addToken(address(token), 100, Votes.getPastVotes.selector);

        assertEq(module.getTokenWeight(address(token)), 100);
        assertEq(module.getTokenSelector(address(token)), Votes.getPastVotes.selector);
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
        MockToken token2 = new MockToken(minter);

        module.addToken(address(token), 5_000, Votes.getPastVotes.selector);
        module.addToken(address(token2), 5_000, Votes.getPastVotes.selector);
        module.removeToken(address(token));

        assertEq(module.getTokenWeight(address(token2)), 5_000);
        assertEq(module.getTokenSelector(address(token2)), Votes.getPastVotes.selector);
        assertEq(module.getTokenAddress(0), address(token2));
    }

    function test_addToken_reverts_alreadyExists() public {
        module.addToken(address(token), 100, Votes.getPastVotes.selector);

        vm.expectRevert(MultiTokenModule.TokenAlreadyExists.selector);
        module.addToken(address(token), 100, Votes.getPastVotes.selector);
    }

    function test_addToken_reverts_invalidToken() public {
        vm.expectRevert(MultiTokenModule.InvalidToken.selector);
        module.addToken(address(0), 100, Votes.getPastVotes.selector);
    }

    function test_addToken_reverts_invalidWeight() public {
        vm.expectRevert(MultiTokenModule.InvalidWeight.selector);
        module.addToken(address(token), 0, Votes.getPastVotes.selector);

        vm.expectRevert(MultiTokenModule.InvalidWeight.selector);
        module.addToken(address(token), 10_001, Votes.getPastVotes.selector);
    }

    function test_addToken_reverts_invalidSelector() public {
        vm.expectRevert(MultiTokenModule.InvalidSelector.selector);
        module.addToken(address(token), 100, bytes4(0));
    }

    function test_castVote_succeeds(uint16 weight) public {
        vm.assume(weight > 0 && weight <= 10_000);

        vm.prank(minter);
        token.mint(address(this), 100e18);
        vm.prank(address(this));
        token.delegate(address(this));

        module.addToken(address(token), weight, Votes.getPastVotes.selector);

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        // vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        uint256 snapshot = block.number + governor.votingDelay();
        vm.roll(snapshot + 1);

        governor.castVote(proposalId, 1);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        assertEq(forVotes, uint256(100e18) * weight / 10_000);
        assertEq(againstVotes, 0);
        assertEq(abstainVotes, 0);
    }

    function test_castVote_succeeds_multipleTokens(uint16 weight1, uint16 weight2) public {
        vm.assume(weight1 > 0 && weight1 <= 10_000);
        vm.assume(weight2 > 0 && weight2 <= 10_000);

        MockToken token2 = new MockToken(minter);

        vm.startPrank(minter);
        token.mint(address(this), 100e18);
        token2.mint(address(this), 100e18);
        vm.stopPrank();

        token.delegate(address(this));
        token2.delegate(address(this));

        module.addToken(address(token), weight1, Votes.getPastVotes.selector);
        module.addToken(address(token2), weight2, Votes.getPastVotes.selector);

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        // vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        uint256 snapshot = block.number + governor.votingDelay();
        vm.roll(snapshot + 1);

        governor.castVote(proposalId, 1);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        assertEq(forVotes, uint256(100e18) * weight1 / 10_000 + uint256(100e18) * weight2 / 10_000);
        assertEq(againstVotes, 0);
        assertEq(abstainVotes, 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";

import {Hooks} from "src/libraries/Hooks.sol";
import {ApprovalVotingModuleMock} from "test/mocks/ApprovalVotingModuleMock.sol";
import {Optimistic, ProposalSettings, Proposal} from "src/modules/Optimistic.sol";
import {Middleware} from "src/Middleware.sol";

import {MockToken} from "test/mocks/MockToken.sol";
import {Deployers} from "test/utils/Deployers.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

enum VoteType {
    Against,
    For,
    Abstain
}

contract OptimisticModuleTest is Test, Deployers {
    Optimistic module;
    Middleware middleware;
    string description = "my description is this one#proposalTypeId=1#proposalData=";
    address internal voter = makeAddr("voter");
    address test1 = makeAddr("test1");
    address test2 = makeAddr("test2");
    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        module = Optimistic(
            address(uint160(Hooks.BEFORE_VOTE_SUCCEEDED_FLAG | Hooks.AFTER_PROPOSE_FLAG | Hooks.BEFORE_EXECUTE_FLAG))
        );

        middleware = Middleware(
            address(
                uint160(
                    Hooks.BEFORE_VOTE_SUCCEEDED_FLAG | Hooks.AFTER_VOTE_SUCCEEDED_FLAG
                        | Hooks.BEFORE_QUORUM_CALCULATION_FLAG | Hooks.AFTER_QUORUM_CALCULATION_FLAG
                        | Hooks.BEFORE_VOTE_FLAG | Hooks.AFTER_VOTE_FLAG | Hooks.BEFORE_PROPOSE_FLAG
                        | Hooks.AFTER_PROPOSE_FLAG | Hooks.BEFORE_CANCEL_FLAG | Hooks.AFTER_CANCEL_FLAG
                        | Hooks.BEFORE_QUEUE_FLAG | Hooks.AFTER_QUEUE_FLAG | Hooks.BEFORE_EXECUTE_FLAG
                        | Hooks.AFTER_EXECUTE_FLAG
                )
            )
        );

        deployGovernor(address(middleware));
        deployCodeTo("src/Middleware.sol:Middleware", abi.encode(address(governor)), address(middleware));
        deployCodeTo(
            "src/modules/Optimistic.sol:Optimistic", abi.encode(address(governor), address(middleware)), address(module)
        );

        vm.prank(address(admin));
        middleware.setProposalType(1, 0, 0, "Alt", "Lorem Ipsum", address(module));
    }

    function test_createProposal() public {
        ProposalSettings memory settings = ProposalSettings({againstThreshold: 50, isRelativeToVotableSupply: true});

        bytes memory proposalData = abi.encode(settings);

        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (test1, 100));
        targets[1] = test2;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        uint256 proposalId = governor.propose(targets, values, calldatas, descriptionWithData);
        vm.stopPrank();

        (, ProposalSettings memory moduleSettings) = Optimistic(module).proposals(proposalId);

        assertEq(moduleSettings.againstThreshold, settings.againstThreshold);
        assertEq(moduleSettings.isRelativeToVotableSupply, settings.isRelativeToVotableSupply);
    }

    function testVoteFor() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        ProposalSettings memory settings = ProposalSettings({againstThreshold: 50, isRelativeToVotableSupply: false});

        bytes memory proposalData = abi.encode(settings);

        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (test1, 100));
        targets[1] = test2;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        uint256 proposalId = governor.propose(targets, values, calldatas, descriptionWithData);
        vm.stopPrank();
        vm.roll(block.number + 2);

        vm.startPrank(voter);
        governor.castVote(proposalId, uint8(VoteType.For));
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        vm.stopPrank();
        assertEq(forVotes, weight);
    }

    function testVoteAgainst() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        ProposalSettings memory settings = ProposalSettings({againstThreshold: 50, isRelativeToVotableSupply: false});

        bytes memory proposalData = abi.encode(settings);

        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (test1, 100));
        targets[1] = test2;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        uint256 proposalId = governor.propose(targets, values, calldatas, descriptionWithData);
        vm.stopPrank();
        vm.roll(block.number + 2);

        vm.startPrank(voter);
        governor.castVote(proposalId, uint8(VoteType.Against));
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        vm.stopPrank();
        assertEq(againstVotes, weight);
    }

    function testVoteAbstain() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        ProposalSettings memory settings = ProposalSettings({againstThreshold: 50, isRelativeToVotableSupply: false});

        bytes memory proposalData = abi.encode(settings);

        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (test1, 100));
        targets[1] = test2;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        uint256 proposalId = governor.propose(targets, values, calldatas, descriptionWithData);
        vm.stopPrank();
        vm.roll(block.number + 2);

        vm.startPrank(voter);
        governor.castVote(proposalId, uint8(VoteType.Abstain));
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        vm.stopPrank();
        assertEq(abstainVotes, weight);
    }

    function testVoteSucceeded() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        ProposalSettings memory settings = ProposalSettings({againstThreshold: 50, isRelativeToVotableSupply: false});

        bytes memory proposalData = abi.encode(settings);

        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (test1, 100));
        targets[1] = test2;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        uint256 proposalId = governor.propose(targets, values, calldatas, descriptionWithData);
        vm.stopPrank();
        vm.roll(block.number + 2);

        vm.startPrank(voter);
        governor.castVote(proposalId, uint8(VoteType.For));

        uint256 snapshot = block.number + governor.votingDelay();
        vm.roll(snapshot + 1);
        (uint256 againstVotes,,) = governor.proposalVotes(proposalId);

        assertTrue(governor.voteSucceeded(proposalId));

        vm.stopPrank();
    }
}

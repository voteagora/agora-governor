// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";

import {Hooks} from "src/libraries/Hooks.sol";
import {ApprovalVotingModuleMock} from "test/mocks/ApprovalVotingModuleMock.sol";
import {
    ApprovalVotingModule,
    ProposalOption,
    ProposalSettings,
    PassingCriteria,
    Proposal
} from "src/modules/ApprovalVoting.sol";
import {Middleware} from "src/Middleware.sol";
import {AgoraGovernor} from "src/AgoraGovernor.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {MockToken} from "test/mocks/MockToken.sol";
import {Deployers} from "test/utils/Deployers.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

enum VoteType {
    Against,
    For,
    Abstain
}

contract ApprovalVotingModuleTest is Test, Deployers {
    uint256 counter;
    ApprovalVotingModuleMock module;
    Middleware middleware;
    string description = "my description is this one#proposalTypeId=1#proposalData=";
    address internal voter = makeAddr("voter");
    address internal altVoter = makeAddr("altVoter");
    address receiver1 = makeAddr("receiver1");
    address receiver2 = makeAddr("receiver2");

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        module = ApprovalVotingModuleMock(
            address(
                uint160(
                    Hooks.BEFORE_VOTE_SUCCEEDED_FLAG | Hooks.AFTER_VOTE_FLAG | Hooks.AFTER_PROPOSE_FLAG
                        | Hooks.BEFORE_QUEUE_FLAG
                )
            )
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
            "test/mocks/ApprovalVotingModuleMock.sol:ApprovalVotingModuleMock",
            abi.encode(address(governor)),
            address(module)
        );

        vm.prank(address(admin));
        middleware.setProposalType(1, 5_000, 7_000, "Alt", "Lorem Ipsum", address(module));
    }

    function executeCallback() public payable virtual {
        counter++;
    }

    function createProposal() internal returns (uint256 proposalId) {
        (bytes memory proposalData,,) = _formatProposalData();

        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (receiver1, 100));
        targets[1] = receiver2;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        proposalId = governor.propose(targets, values, calldatas, descriptionWithData);
        vm.stopPrank();
    }

    function test_createProposal() public {
        (, ProposalOption[] memory options, ProposalSettings memory settings) = _formatProposalData();

        uint256 proposalId = createProposal();
        Proposal memory proposal = ApprovalVotingModuleMock(module)._proposals(proposalId);

        assertEq(proposal.optionVotes[0], 0);
        assertEq(proposal.optionVotes[1], 0);
        assertEq(proposal.optionVotes[2], 0);
        assertEq(proposal.settings.maxApprovals, settings.maxApprovals);
        assertEq(proposal.settings.criteria, settings.criteria);
        assertEq(proposal.settings.budgetToken, settings.budgetToken);
        assertEq(proposal.settings.criteriaValue, settings.criteriaValue);
        assertEq(proposal.settings.budgetAmount, settings.budgetAmount);
        assertEq(proposal.options[0].targets[0], options[0].targets[0]);
        assertEq(proposal.options[0].values[0], options[0].values[0]);
        assertEq(proposal.options[0].calldatas[0], options[0].calldatas[0]);
        assertEq(proposal.options[0].description, options[0].description);
        assertEq(proposal.options[1].targets[0], options[1].targets[0]);
        assertEq(proposal.options[1].values[0], options[1].values[0]);
        assertEq(proposal.options[1].calldatas[0], options[1].calldatas[0]);
        assertEq(proposal.options[1].targets[1], options[1].targets[1]);
        assertEq(proposal.options[1].values[1], options[1].values[1]);
        assertEq(proposal.options[1].calldatas[1], options[1].calldatas[1]);
        assertEq(proposal.options[1].description, options[1].description);
    }

    function testCountVote_voteForSingle() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        uint256 proposalId = createProposal();
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 0;
        bytes memory params = abi.encode(votes);

        assertEq(module.getAccountTotalVotes(proposalId, voter), 0);
        vm.startPrank(voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);

        Proposal memory proposal = module._proposals(proposalId);

        assertEq(module.getAccountTotalVotes(proposalId, voter), votes.length);
        assertEq(proposal.optionVotes[0], weight);
        assertEq(proposal.optionVotes[1], 0);
        assertEq(proposal.optionVotes[2], 0);

        vm.stopPrank();
    }

    function testCountVote_voteForMultiple() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        uint256 proposalId = createProposal();
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 0;
        votes[1] = 1;
        bytes memory params = abi.encode(votes);

        assertEq(module.getAccountTotalVotes(proposalId, voter), 0);
        vm.startPrank(voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);

        Proposal memory proposal = module._proposals(proposalId);

        assertEq(module.getAccountTotalVotes(proposalId, voter), votes.length);
        assertEq(proposal.optionVotes[0], weight);
        assertEq(proposal.optionVotes[1], weight);
        assertEq(proposal.optionVotes[2], 0);

        vm.stopPrank();
    }

    function testCountVote_voteAgainst() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        uint256 proposalId = createProposal();
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 0;
        bytes memory params = abi.encode(votes);

        assertEq(module.getAccountTotalVotes(proposalId, voter), 0);
        vm.startPrank(voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.Against), "a good reason", params);

        Proposal memory proposal = module._proposals(proposalId);

        assertEq(module.getAccountTotalVotes(proposalId, voter), 0);
        assertEq(proposal.optionVotes[0], 0);
        assertEq(proposal.optionVotes[1], 0);
        assertEq(proposal.optionVotes[2], 0);

        vm.stopPrank();
    }

    function testCountVote_voteAbstain() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        uint256 proposalId = createProposal();
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 0;
        bytes memory params = abi.encode(votes);

        assertEq(module.getAccountTotalVotes(proposalId, voter), 0);
        vm.startPrank(voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.Abstain), "a good reason", params);

        Proposal memory proposal = module._proposals(proposalId);

        assertEq(module.getAccountTotalVotes(proposalId, voter), 0);
        assertEq(proposal.optionVotes[0], 0);
        assertEq(proposal.optionVotes[1], 0);
        assertEq(proposal.optionVotes[2], 0);

        vm.stopPrank();
    }

    function testVoteSucceeded() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        uint256 proposalId = createProposal();
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](1);
        bytes memory params = abi.encode(votes);

        vm.startPrank(voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);

        assertTrue(governor.voteSucceeded(proposalId));

        vm.stopPrank();
    }

    function testProposalExecutes(address _actor, uint256 _elapsedAfterQueuing) public {
        vm.assume(_actor != proxyAdmin);
        vm.assume(_actor != address(middleware));
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(this);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);
        targets[1] = address(this);
        values[1] = 0;
        calldatas[1] = abi.encodeWithSelector(this.executeCallback.selector);

        ProposalOption[] memory options = new ProposalOption[](1);
        options[0] = ProposalOption(100, targets, values, calldatas, "option 1");

        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 2,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 1,
            budgetToken: address(token),
            budgetAmount: 100
        });

        bytes memory proposalData = abi.encode(options, settings);

        string memory descriptionWithData = string.concat(description, string(proposalData));

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        uint256 proposalId = governor.propose(targets, values, calldatas, descriptionWithData);
        vm.stopPrank();
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 0;
        bytes memory params = abi.encode(votes);

        vm.startPrank(voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);
        vm.stopPrank();

        vm.roll(block.number + 14);

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256(bytes(descriptionWithData)));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(_actor);
        governor.execute(targets, values, calldatas, keccak256(bytes(descriptionWithData)));

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
        assertEq(counter, 2);

        vm.stopPrank();
    }

    function testSortOptions() public view {
        (, ProposalOption[] memory options,) = _formatProposalData();

        uint128[] memory optionVotes = new uint128[](3);
        optionVotes[0] = 0;
        optionVotes[1] = 10;
        optionVotes[2] = 2;

        (uint128[] memory sortedOptionVotes, ProposalOption[] memory sortedOptions) =
            module.sortOptions(optionVotes, options);

        assertEq(sortedOptionVotes[0], optionVotes[1]);
        assertEq(sortedOptions[0].targets[0], options[1].targets[0]);
        assertEq(sortedOptionVotes[1], optionVotes[2]);
        assertEq(sortedOptions[1].targets[0], options[2].targets[0]);
        assertEq(sortedOptionVotes[2], optionVotes[0]);
        assertEq(sortedOptions[2].targets[0], options[0].targets[0]);
    }

    function testCountOptions_criteriaTopChoices(uint128[3] memory _optionVotes) public view {
        (, ProposalOption[] memory options, ProposalSettings memory settings) = _formatProposalData();

        uint128[] memory optionVotes = new uint128[](3);
        optionVotes[0] = _optionVotes[0];
        optionVotes[1] = _optionVotes[1];
        optionVotes[2] = _optionVotes[2];

        (uint128[] memory sortedOptionVotes, ProposalOption[] memory sortedOptions) =
            module.sortOptions(optionVotes, options);

        // count proposals with more than zero votes
        uint256 succesfulVotes = 0;
        for (uint256 i = 0; i < sortedOptionVotes.length; i++) {
            if (sortedOptionVotes[i] > 0) {
                succesfulVotes++;
            } else {
                break;
            }
        }

        (uint256 executeParamsLength, uint256 succeededOptionsLength) =
            module.countOptions(sortedOptions, sortedOptionVotes, settings);

        assertEq(
            succeededOptionsLength, settings.criteriaValue < succesfulVotes ? settings.criteriaValue : succesfulVotes
        );
        assertLe(
            executeParamsLength,
            sortedOptions[0].targets.length + sortedOptions[1].targets.length + sortedOptions[2].targets.length
        );
    }

    function testCountOptions_criteriaThreshold() public view {
        (, ProposalOption[] memory options, ProposalSettings memory settings) = _formatProposalData();
        settings.criteria = uint8(PassingCriteria.Threshold);

        uint128[] memory optionVotes = new uint128[](3);
        optionVotes[0] = 0;
        optionVotes[1] = 10;
        optionVotes[2] = 2;

        (uint128[] memory sortedOptionVotes, ProposalOption[] memory sortedOptions) =
            module.sortOptions(optionVotes, options);
        (uint256 executeParamsLength, uint256 succeededOptionsLength) =
            module.countOptions(sortedOptions, sortedOptionVotes, settings);

        assertEq(succeededOptionsLength, 2);
        assertEq(executeParamsLength, sortedOptions[0].targets.length + sortedOptions[1].targets.length);

        settings.criteriaValue = 3;

        (executeParamsLength, succeededOptionsLength) = module.countOptions(sortedOptions, sortedOptionVotes, settings);

        assertEq(succeededOptionsLength, 1);
        assertEq(executeParamsLength, sortedOptions[0].targets.length);
    }

    function testFormatExecuteParams() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        (, ProposalOption[] memory options,) = _formatProposalData();

        uint256 proposalId = createProposal();
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 1;
        votes[1] = 2;
        bytes memory params = abi.encode(votes);

        vm.startPrank(voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            module.formatExecuteParams(proposalId);

        uint256 _totalValue = options[1].values[0] + options[1].values[1] + options[2].values[0];

        assertEq(targets.length, options[1].targets.length + options[2].targets.length + 1);
        assertEq(targets.length, values.length);
        assertEq(targets.length, calldatas.length);
        assertEq(targets[0], options[1].targets[0]);
        assertEq(values[0], options[1].values[0]);
        assertEq(calldatas[0], options[1].calldatas[0]);
        assertEq(targets[1], options[1].targets[1]);
        assertEq(values[1], options[1].values[1]);
        assertEq(calldatas[1], options[1].calldatas[1]);
        assertEq(targets[2], options[2].targets[0]);
        assertEq(values[2], options[2].values[0]);
        assertEq(calldatas[2], options[2].calldatas[0]);
        assertEq(targets[3], address(module));
        assertEq(values[3], 0);
        assertEq(calldatas[3], abi.encodeCall(ApprovalVotingModule.checkBudget, (proposalId, _totalValue)));

        vm.stopPrank();
    }

    function testFormatExecuteParams_ethBudgetExceeded() public {
        address[] memory targets1 = new address[](1);
        uint256[] memory values1 = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets1[0] = receiver1;
        values1[0] = 0.6 ether;

        address[] memory targets2 = new address[](1);
        uint256[] memory values2 = new uint256[](1);
        targets2[0] = receiver1;
        values2[0] = 0;

        ProposalOption[] memory options = new ProposalOption[](2);
        options[0] = ProposalOption(0, targets1, values1, calldatas, "option 1");
        options[1] = ProposalOption(0, targets2, values2, calldatas, "option 2");

        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 2,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 2,
            budgetToken: address(0),
            budgetAmount: 0
        });

        bytes memory proposalData = abi.encode(options, settings);

        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targetsI = new address[](2);
        uint256[] memory valuesI = new uint256[](2);
        bytes[] memory calldatasI = new bytes[](2);
        targetsI[0] = address(token);
        calldatasI[0] = abi.encodeCall(IERC20.transfer, (receiver1, 100));
        targetsI[1] = receiver2;
        valuesI[1] = 0.2 ether;
        calldatasI[1] = calldatasI[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        uint256 proposalId = governor.propose(targetsI, valuesI, calldatasI, descriptionWithData);
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 0;
        votes[0] = 1;
        bytes memory params = abi.encode(votes);

        vm.startPrank(voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);

        (address[] memory targets, uint256[] memory values,) = module.formatExecuteParams(proposalId);
        vm.stopPrank();

        assertEq(targets.length, options.length);
        assertEq(targets.length, values.length);
        assertEq(targets[0], options[1].targets[0]);
        assertEq(values[0], options[1].values[0]);
        assertEq(targets[1], address(module));
        assertEq(values[1], 0);
    }

    function testFormatExecuteParams_opBudgetExceeded() public {
        (bytes memory proposalData, ProposalOption[] memory options,) = _formatProposalData(true, true);
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targetsI = new address[](2);
        uint256[] memory valuesI = new uint256[](2);
        bytes[] memory calldatasI = new bytes[](2);
        targetsI[0] = address(token);
        calldatasI[0] = abi.encodeCall(IERC20.transfer, (receiver1, 100));
        targetsI[1] = receiver2;
        valuesI[1] = 0.2 ether;
        calldatasI[1] = calldatasI[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        uint256 proposalId = governor.propose(targetsI, valuesI, calldatasI, descriptionWithData);
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 1;
        bytes memory params = abi.encode(votes);

        vm.startPrank(voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);
        vm.stopPrank();

        votes = new uint256[](1);
        votes[0] = 1;
        params = abi.encode(votes);

        vm.startPrank(altVoter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);
        vm.stopPrank();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            module.formatExecuteParams(proposalId);

        assertEq(targets.length, options[1].targets.length + 1);
        assertEq(targets.length, values.length);
        assertEq(targets.length, calldatas.length);
        assertEq(targets[0], options[1].targets[0]);
        assertEq(values[0], options[1].values[0]);
        assertEq(calldatas[0], options[1].calldatas[0]);
        assertEq(targets[1], address(module));
        assertEq(values[1], 0);
        assertEq(
            calldatas[1], abi.encodeCall(ApprovalVotingModule.checkBudget, (proposalId, options[1].budgetTokensSpent))
        );
    }

    function testGetAccountVotes() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        uint256 proposalId = createProposal();
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 0;
        votes[1] = 1;
        bytes memory params = abi.encode(votes);

        vm.startPrank(voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);
        vm.stopPrank();

        assertEq(module.getAccountVotes(proposalId, voter)[0], 0);
        assertEq(module.getAccountVotes(proposalId, voter)[1], 1);
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_propose_existingProposal() public {
        (bytes memory proposalData,,) = _formatProposalData();

        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (receiver1, 100));
        targets[1] = receiver2;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        governor.propose(targets, values, calldatas, descriptionWithData);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, descriptionWithData);
    }

    function testRevert_propose_invalidProposalData() public {
        bytes memory proposalData = abi.encode(0x12345678);

        // This is ignored
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (receiver1, 100));
        targets[1] = receiver2;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.prank(admin);
        governor.setProposalThreshold(0);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, string(proposalData));
    }

    function testRevert_propose_invalidParams_noOptions() public {
        ProposalOption[] memory options = new ProposalOption[](0);
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 1,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 1,
            budgetToken: address(0),
            budgetAmount: 1 ether
        });

        bytes memory proposalData = abi.encode(options, settings);

        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (receiver1, 100));
        targets[1] = receiver2;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        vm.expectRevert(Hooks.HookCallFailed.selector);
        governor.propose(targets, values, calldatas, descriptionWithData);
    }

    function testRevert_propose_invalidParams_lengthMismatch() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](0);
        ProposalOption[] memory options = new ProposalOption[](1);
        options[0] = ProposalOption(0, targets, values, calldatas, "option");
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 1,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 1,
            budgetToken: address(0),
            budgetAmount: 1 ether
        });

        bytes memory proposalData = abi.encode(options, settings);
        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targetsI = new address[](2);
        uint256[] memory valuesI = new uint256[](2);
        bytes[] memory calldatasI = new bytes[](2);
        targetsI[0] = address(token);
        calldatasI[0] = abi.encodeCall(IERC20.transfer, (receiver1, 100));
        targetsI[1] = receiver2;
        valuesI[1] = 0.2 ether;
        calldatasI[1] = calldatasI[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        vm.expectRevert(Hooks.HookCallFailed.selector);
        governor.propose(targetsI, valuesI, calldatasI, descriptionWithData);
    }

    function testRevert_propose_maxChoicesExceeded() public {
        ProposalOption[] memory options = new ProposalOption[](2);
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 1,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 3,
            budgetToken: address(0),
            budgetAmount: 1 ether
        });

        bytes memory proposalData = abi.encode(options, settings);

        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (receiver1, 100));
        targets[1] = receiver2;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        vm.expectRevert(Hooks.HookCallFailed.selector);
        governor.propose(targets, values, calldatas, descriptionWithData);
    }

    function testRevert_propose_invalidCastVoteData() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        uint256 proposalId = createProposal();
        vm.roll(block.number + 2);

        bytes memory params = abi.encode(0x12345678);

        vm.startPrank(voter);
        vm.expectRevert();
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);
        vm.stopPrank();
    }

    function testRevert_countVote_invalidParams() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        uint256 proposalId = createProposal();
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](0);
        bytes memory params = abi.encode(votes);

        vm.startPrank(voter);
        vm.expectRevert();
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);
        vm.stopPrank();
    }

    function testRevert_countVote_maxApprovalsExceeded() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        uint256 proposalId = createProposal();
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](3);
        votes[0] = 0;
        votes[1] = 1;
        votes[2] = 2;
        bytes memory params = abi.encode(votes);

        vm.startPrank(voter);
        vm.expectRevert();
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);
        vm.stopPrank();
    }

    function testRevert_countVote_optionsNotStrictlyAscending() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        uint256 proposalId = createProposal();
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 1;
        votes[1] = 0;
        bytes memory params = abi.encode(votes);

        vm.startPrank(voter);
        vm.expectRevert();
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);
        vm.stopPrank();
    }

    function testRevert_countVote_optionsExceeded() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        uint256 proposalId = createProposal();
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](4);
        votes[0] = 0;
        votes[1] = 1;
        votes[2] = 2;
        votes[3] = 4;
        bytes memory params = abi.encode(votes);

        vm.startPrank(voter);
        //ApprovalVotingModule.InvalidParams.selector
        vm.expectRevert();
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);
        vm.stopPrank();
    }

    function testRevert_countVote_outOfBounds() public {
        uint256 weight = 100;
        vm.prank(minter);
        token.mint(voter, weight);

        vm.startPrank(voter);
        token.delegate(voter);
        vm.roll(block.number + 1);
        vm.stopPrank();

        uint256 proposalId = createProposal();
        vm.roll(block.number + 2);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 2;
        votes[1] = 3;
        bytes memory params = abi.encode(votes);

        vm.startPrank(voter);
        vm.expectRevert();
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);
        vm.stopPrank();
    }

    function testReverts_formatExecuteParams_nativeMix() public {
        address[] memory _targets = new address[](2);
        uint256[] memory _values = new uint256[](2);
        bytes[] memory _calldatas = new bytes[](2);
        // Token transfer
        _targets[0] = address(token);
        _values[0] = 0;
        _calldatas[0] = abi.encodeCall(IERC20.transfer, (receiver1, 100));
        // Native transfer
        _targets[1] = receiver1;
        _values[1] = 0.01 ether;

        ProposalOption[] memory options = new ProposalOption[](1);
        options[0] = ProposalOption(100, _targets, _values, _calldatas, "option 1");

        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 2,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 1,
            budgetToken: address(token),
            budgetAmount: 100
        });

        bytes memory proposalData = abi.encode(options, settings);

        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (receiver1, 100));
        targets[1] = receiver2;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, descriptionWithData);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _formatProposalData(bool budgetExceeded, bool isBudgetOp)
        internal
        view
        returns (bytes memory proposalData, ProposalOption[] memory options, ProposalSettings memory settings)
    {
        address[] memory targets1 = new address[](1);
        uint256[] memory values1 = new uint256[](1);
        bytes[] memory calldatas1 = new bytes[](1);
        // Send 0.01 ether to receiver1
        targets1[0] = receiver1;
        values1[0] = budgetExceeded ? 0.6 ether : 0.01 ether;

        address[] memory targets2 = new address[](2);
        uint256[] memory values2 = new uint256[](2);
        bytes[] memory calldatas2 = new bytes[](2);
        // Transfer 100 OP tokens to receiver2
        targets2[0] = address(token);
        calldatas2[0] = abi.encodeCall(IERC20.transfer, (receiver1, budgetExceeded ? 6e17 : 100));
        targets2[1] = receiver2;
        values2[1] = (!isBudgetOp && budgetExceeded) ? 0.6 ether : 0;
        calldatas2[1] = calldatas2[0];

        address[] memory targets3 = new address[](1);
        uint256[] memory values3 = new uint256[](1);
        bytes[] memory calldatas3 = new bytes[](1);
        targets3[0] = address(token);
        calldatas3[0] = abi.encodeCall(IERC20.transferFrom, (address(governor), receiver1, budgetExceeded ? 6e17 : 100));

        if (isBudgetOp) {
            options = new ProposalOption[](2);
            options[0] = ProposalOption(budgetExceeded ? 6e17 : 100, targets2, values2, calldatas2, "option 2");
            options[1] = ProposalOption(budgetExceeded ? 6e17 : 100, targets3, values3, calldatas3, "option 3");
        } else {
            options = new ProposalOption[](3);
            options[0] = ProposalOption(0, targets1, values1, calldatas1, "option 1");
            options[1] = ProposalOption(budgetExceeded ? 6e17 : 100, targets2, values2, calldatas2, "option 2");
            options[2] = ProposalOption(budgetExceeded ? 6e17 : 100, targets3, values3, calldatas3, "option 3");
        }

        settings = ProposalSettings({
            maxApprovals: 2,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 2,
            budgetToken: isBudgetOp ? address(token) : address(0),
            budgetAmount: 1e18
        });

        proposalData = abi.encode(options, settings);
    }

    function _formatProposalData()
        internal
        view
        returns (bytes memory proposalData, ProposalOption[] memory options, ProposalSettings memory settings)
    {
        return _formatProposalData(false, false);
    }
}

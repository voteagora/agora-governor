// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";

import {Hooks} from "src/libraries/Hooks.sol";
import {WorldIDVotingMock} from "test/mocks/WorldIDVotingMock.sol";
import {
    WorldIDVoting,
    ProposalOption,
    ProposalSettings,
    PassingCriteria,
    Proposal,
    IWorldID
} from "src/modules/WorldIDVoting.sol";
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

contract WorldIDVotingModuleTest is Test, Deployers {
    uint256 counter;
    WorldIDVotingMock module;
    Middleware middleware;
    string description = "foo#proposalTypeId=2#proposalData=";
    address internal voter = makeAddr("voter");
    address internal altVoter = makeAddr("altVoter");
    address receiver1 = makeAddr("receiver1");
    address receiver2 = makeAddr("receiver2");

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        module = WorldIDVotingMock(
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
            "test/mocks/WorldIDVotingMock.sol:WorldIDVotingMock",
            abi.encode(
                address(governor), address(middleware), IWorldID(0x17B354dD2595411ff79041f930e491A4Df39A278), "app_id"
            ),
            address(module)
        );

        vm.startPrank(address(admin));
        middleware.setProposalType(1, 5_000, 7_000, "Alt", "Lorem Ipsum", address(module));
        middleware.setProposalType(2, 5_000, 7_000, "Alt", "Lorem Ipsum", address(module));
        vm.stopPrank();
    }

    function executeCallback() public payable virtual {
        counter++;
    }

    function createProposal() internal returns (uint256 proposalId) {
        (bytes memory proposalData,,) = _formatProposalData();
        console.logBytes(proposalData);

        string memory descriptionWithData = string.concat(description, string(proposalData));

        // This is ignored
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (receiver1, 100));

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        proposalId = governor.propose(targets, values, calldatas, descriptionWithData);
        vm.stopPrank();
    }

    function test_createProposal() public {
        (, ProposalOption[] memory options, ProposalSettings memory settings) = _formatProposalData();

        uint256 proposalId = createProposal();
        Proposal memory proposal = WorldIDVotingMock(module)._proposals(proposalId);

        assertEq(proposal.optionVotes[0], 0);
        assertEq(proposal.optionVotes[1], 0);
        assertEq(proposal.settings.maxApprovals, settings.maxApprovals);
        assertEq(proposal.settings.criteria, settings.criteria);
        assertEq(proposal.settings.criteriaValue, settings.criteriaValue);
        assertEq(proposal.settings.isSignalVote, settings.isSignalVote);
        assertEq(proposal.options[0].description, options[0].description);
        assertEq(proposal.options[1].description, options[1].description);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _formatProposalData()
        internal
        view
        returns (bytes memory proposalData, ProposalOption[] memory options, ProposalSettings memory settings)
    {
        options = new ProposalOption[](2);
        options[0] = ProposalOption("option 1");
        options[1] = ProposalOption("option 2");

        settings = ProposalSettings({
            minParticipation: 3,
            maxApprovals: 2,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 2,
            isSignalVote: true,
            actionId: "foobar"
        });

        proposalData = abi.encode(options, settings);
    }
}

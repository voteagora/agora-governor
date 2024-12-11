// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {AgoraGovernor} from "src/AgoraGovernor.sol";

import {MockToken} from "test/mocks/MockToken.sol";

contract AgoraGovernorTest is Test {
    // Contracts
    AgoraGovernor public governor;
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
    uint256 quorumNumerator = 50;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        vm.startPrank(deployer);

        // Deploy token
        token = new MockToken(minter);

        // Calculate governor address
        address governorAddress = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);

        // Deploy timelock
        address[] memory proposers = new address[](1);
        proposers[0] = governorAddress;
        address[] memory executors = new address[](1);
        executors[0] = governorAddress;
        timelock = new TimelockController(timelockDelay, proposers, executors, deployer);

        // Deploy governor
        governor = new AgoraGovernor(
            votingDelay, votingPeriod, proposalThreshold, quorumNumerator, token, timelock, admin, manager
        );

        vm.stopPrank();
    }

    function executeCallback() public payable virtual {}
}

contract Propose is AgoraGovernorTest {
    function test_propose_validInput_succeeds(address _actor, uint256 _proposalThreshold, uint256 _actorBalance)
        public
        virtual
    {
        vm.assume(_actor != manager && _actor != address(0) && _actor != proxyAdmin);
        _proposalThreshold = bound(_proposalThreshold, 0, type(uint208).max);
        _actorBalance = bound(_actorBalance, _proposalThreshold, type(uint208).max);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(admin);
        governor.setProposalThreshold(_proposalThreshold);

        // Give actor enough tokens to meet proposal threshold.
        vm.prank(minter);
        token.mint(_actor, _actorBalance);
        vm.startPrank(_actor);
        token.delegate(_actor);
        vm.roll(block.number + 1);

        uint256 proposalId;
        proposalId = governor.propose(targets, values, calldatas, "Test");
        vm.stopPrank();
        assertGt(governor.proposalSnapshot(proposalId), 0);
    }

    function test_propose_manager_succeeds(uint256 _proposalThreshold) public virtual {
        _proposalThreshold = bound(_proposalThreshold, 0, type(uint208).max);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(admin);
        governor.setProposalThreshold(_proposalThreshold);

        uint256 proposalId;
        vm.prank(manager);
        proposalId = governor.propose(targets, values, calldatas, "Test");
        assertGt(governor.proposalSnapshot(proposalId), 0);
    }

    function test_propose_thresholdNotMet_reverts(address _actor, uint256 _proposalThreshold, uint256 _actorBalance)
        public
        virtual
    {
        vm.assume(_actor != manager && _actor != address(0) && _actor != proxyAdmin);
        _proposalThreshold = bound(_proposalThreshold, 1, type(uint208).max);
        _actorBalance = bound(_actorBalance, 0, _proposalThreshold - 1);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(admin);
        governor.setProposalThreshold(_proposalThreshold);

        // Give actor some tokens, but not enough to meet proposal threshold
        vm.prank(minter);
        token.mint(_actor, _actorBalance);
        vm.startPrank(_actor);
        token.delegate(_actor);
        vm.roll(block.number + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorInsufficientProposerVotes.selector, _actor, _actorBalance, _proposalThreshold
            )
        );
        governor.propose(targets, values, calldatas, "Test");
    }

    function test_propose_alreadyCreated_reverts() public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector, proposalId, governor.state(proposalId), bytes32(0)
            )
        );
        governor.propose(targets, values, calldatas, "Test");
        vm.stopPrank();
    }
}

contract Queue is AgoraGovernorTest {
    function test_queue_validInput_succeeds(
        address _actor,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.assume(_actor != proxyAdmin);
        vm.prank(minter);
        token.mint(address(this), 1e30);
        token.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);
        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 14);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
        vm.prank(_actor);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));
    }

    // TODO: test that non-passing proposals can't be queued (aka voting period over)
    function test_queue_manager_succeeds(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        token.mint(address(this), 1e30);
        token.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);
        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 14);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));
    }

    function test_queue_notSucceeded_reverts(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        token.mint(address(this), 1e30);
        token.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);
        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                proposalId,
                governor.state(proposalId),
                bytes32(1 << uint8(IGovernor.ProposalState.Succeeded))
            )
        );
        governor.queue(targets, values, calldatas, keccak256("Test"));
    }

    function test_queue_alreadyQueued_reverts(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        token.mint(address(this), 1e30);
        token.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 14);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                proposalId,
                governor.state(proposalId),
                bytes32(1 << uint8(IGovernor.ProposalState.Succeeded))
            )
        );
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));
    }
}

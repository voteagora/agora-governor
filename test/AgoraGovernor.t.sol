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
    uint256 counter;

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

    function executeCallback() public payable virtual {
        counter++;
    }

    function _adminOrTimelock(uint256 _actorSeed) internal view returns (address) {
        if (_actorSeed % 2 == 1) return admin;
        else return address(timelock);
    }
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

contract Execute is AgoraGovernorTest {
    function test_execute_validInput_succeeds(
        address _actor,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public virtual {
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

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(_actor);
        governor.execute(targets, values, calldatas, keccak256("Test"));

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
        assertEq(counter, 1);
    }

    function test_execute_manager_succeeds(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing)
        public
        virtual
    {
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

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
        assertEq(counter, 1);
    }

    function test_execute_notQueued_reverts(uint256 _proposalTargetCalldata) public {
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

        bytes32 id = timelock.hashOperationBatch(
            targets, values, calldatas, bytes32(0), bytes20(address(governor)) ^ keccak256("Test")
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                bytes32(1 << uint8(TimelockController.OperationState.Ready))
            )
        );
        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));
    }

    function test_execute_notReady_reverts(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, 0, timelock.getMinDelay() - 1);
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

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        bytes32 id = timelock.hashOperationBatch(
            targets, values, calldatas, bytes32(0), bytes20(address(governor)) ^ keccak256("Test")
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                bytes32(1 << uint8(TimelockController.OperationState.Ready))
            )
        );
        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));
    }

    function test_execute_notSuccessful_reverts(uint256 _proposalTargetCalldata) public {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        vm.startPrank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                proposalId,
                governor.state(proposalId),
                bytes32(1 << uint8(IGovernor.ProposalState.Succeeded))
                    | bytes32(1 << uint8(IGovernor.ProposalState.Queued))
            )
        );
        governor.execute(targets, values, calldatas, keccak256("Test"));
    }

    function test_execute_alreadyExecuted_reverts(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing)
        public
    {
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

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                proposalId,
                governor.state(proposalId),
                bytes32(1 << uint8(IGovernor.ProposalState.Succeeded))
                    | bytes32(1 << uint8(IGovernor.ProposalState.Queued))
            )
        );
        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));
    }
}

contract Cancel is AgoraGovernorTest {
    function test_cancel_beforeQueuing_succeeds(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing,
        uint256 _actorSeed
    ) public virtual {
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

        vm.prank(_adminOrTimelock(_actorSeed));
        governor.cancel(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }

    function test_cancel_afterQueuing_succeeds(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing,
        uint256 _actorSeed
    ) public virtual {
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

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));
        vm.prank(_adminOrTimelock(_actorSeed));
        governor.cancel(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }

    function test_cancel_beforeVoteEnd_succeeds(uint256 _actorSeed) public virtual {
        vm.prank(minter);
        token.mint(address(this), 1000);
        token.delegate(address(this));

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

        vm.prank(_adminOrTimelock(_actorSeed));
        governor.cancel(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }

    function test_cancel_afterExecution_reverts(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing,
        uint256 _actorSeed
    ) public virtual {
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

        vm.startPrank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);
        governor.execute(targets, values, calldatas, keccak256("Test"));
        vm.stopPrank();

        bytes32 all = bytes32((2 ** (uint8(type(IGovernor.ProposalState).max) + 1)) - 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                proposalId,
                governor.state(proposalId),
                all ^ bytes32(1 << uint8(IGovernor.ProposalState.Canceled))
                    ^ bytes32(1 << uint8(IGovernor.ProposalState.Expired))
                    ^ bytes32(1 << uint8(IGovernor.ProposalState.Executed))
            )
        );
        vm.prank(_adminOrTimelock(_actorSeed));
        governor.cancel(targets, values, calldatas, keccak256("Test"));
    }

    function test_cancel_noProposal_reverts(uint256 _actorSeed) public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        uint256 proposalId = governor.hashProposal(targets, values, calldatas, keccak256("Test"));

        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorNonexistentProposal.selector, proposalId));
        governor.cancel(targets, values, calldatas, keccak256("Test"));
    }
}

contract UpdateTimelock is AgoraGovernorTest {
    function testFuzz_UpdateTimelock(uint256 _elapsedAfterQueuing, address _newTimelock) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        token.mint(address(this), 1e30);
        token.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(governor);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(governor.updateTimelock.selector, address(_newTimelock));

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 14);

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));
        assertEq(governor.timelock(), address(_newTimelock));
    }

    function testFuzz_RevertIf_NotTimelock(address _actor, address _newTimelock) public {
        vm.assume(_actor != governor.timelock() && _actor != proxyAdmin);
        vm.prank(_actor);
        vm.expectRevert("Governor: onlyGovernance");
        governor.updateTimelock(TimelockControllerUpgradeable(payable(_newTimelock)));
    }
}

contract Quorum is AgoraGovernorTest {
    function test_CorrectlyCalculatesQuorum(address _voter, uint208 _amount) public virtual {
        _mintAndDelegate(_voter, _amount);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + governor.votingDelay() + 1);

        uint256 supply = token.totalSupply();
        uint256 quorum = governor.quorum(proposalId);
        assertEq(quorum, (supply * 3) / 10);
    }
}

contract QuorumReached is AgoraGovernorTest {
    function test_CorrectlyReturnsQuorumStatus(address _voter, address _voter2) public virtual {
        vm.assume(_voter != _voter2);
        _mintAndDelegate(_voter, 30e18);
        _mintAndDelegate(_voter2, 100e18);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        uint256 snapshot = block.number + governor.votingDelay();
        vm.roll(snapshot + 1);

        assertFalse(governor.quorumReached(proposalId));

        vm.prank(_voter);
        governor.castVote(proposalId, 1);

        assertFalse(governor.quorumReached(proposalId));

        vm.prank(_voter2);
        governor.castVote(proposalId, 1);

        assertTrue(governor.quorumReached(proposalId));
    }
}

contract CastVote is AgoraGovernorTest {
    function testFuzz_VoteSucceeded(address _voter, address _voter2) public virtual {
        vm.assume(_voter != _voter2);
        _mintAndDelegate(_voter, 100e18);
        _mintAndDelegate(_voter2, 100e18);
        vm.prank(admin);
        proposalTypesConfigurator.setProposalType(0, 3_000, 9_910, "Default", "Lorem Ipsum", address(0));
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        uint256 snapshot = block.number + governor.votingDelay();
        vm.roll(snapshot + 1);

        vm.prank(_voter);
        governor.castVote(proposalId, 1);
        vm.prank(_voter2);
        governor.castVote(proposalId, 0);

        assertFalse(governor.voteSucceeded(proposalId));

        vm.prank(manager);
        proposalId = governor.propose(targets, values, calldatas, "Test2");

        snapshot = block.number + governor.votingDelay();
        vm.roll(snapshot + 1);

        vm.prank(_voter);
        governor.castVote(proposalId, 1);

        assertTrue(governor.voteSucceeded(proposalId));
    }
}

contract CastVoteWithReasonAndParams is AgoraGovernorTest {
    function test_CastVoteWithModule(address _voter, address _voter2) public virtual {
        vm.assume(_voter != _voter2);
        _mintAndDelegate(_voter, 1e18);
        _mintAndDelegate(_voter2, 1e20);
        bytes memory proposalData = _formatProposalData(0);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 weight = token.getVotes(_voter);
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        vm.expectEmit(true, false, false, true);
        emit VoteCastWithParams(_voter, proposalId, uint8(VoteType.For), weight, reason, params);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        weight = token.getVotes(_voter2);
        vm.prank(_voter2);
        vm.expectEmit(true, false, false, true);
        emit VoteCastWithParams(_voter2, proposalId, uint8(VoteType.Against), weight, reason, params);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.Against), reason, params);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        assertEq(againstVotes, 1e20);
        assertEq(forVotes, 1e18);
        assertEq(abstainVotes, 0);
        assertFalse(governor.voteSucceeded(proposalId));
        assertEq(module._proposals(proposalId).optionVotes[0], 1e18);
        assertEq(module._proposals(proposalId).optionVotes[1], 0);
        assertTrue(governor.hasVoted(proposalId, _voter));
        assertEq(module.getAccountTotalVotes(proposalId, _voter), optionVotes.length);
        assertTrue(governor.hasVoted(proposalId, _voter2));
        assertEq(module.getAccountTotalVotes(proposalId, _voter2), 0);
    }

    function test_RevertIf_voteNotActive(address _voter) public virtual {
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(0);
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        vm.expectRevert("Governor: vote not currently active");
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);
    }

    function test_HasVoted(address _voter) public virtual {
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(0);
        uint256 snapshot = block.number + governor.votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        assertTrue(governor.hasVoted(proposalId, _voter));
    }
}

contract VoteSucceeded is AgoraGovernorTest {
    function test_QuorumReachedAndVoteSucceeded(address _voter) public virtual {
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(0);
        uint256 snapshot = block.number + governor.votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        assertTrue(governor.quorum(proposalId) != 0);
        assertTrue(governor.quorumReached(proposalId));
        assertTrue(governor.voteSucceeded(proposalId));
    }

    function test_VoteNotSucceeded(address _voter, address _voter2) public virtual {
        vm.assume(_voter != _voter2);
        _mintAndDelegate(_voter, 100e18);
        _mintAndDelegate(_voter2, 200e18);
        bytes memory proposalData = _formatProposalData(0);
        uint256 snapshot = block.number + governor.votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.prank(_voter2);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.Against), reason, "");

        assertTrue(governor.quorum(proposalId) != 0);
        assertFalse(governor.voteSucceeded(proposalId));
    }
}

contract SetProposalDeadline is AgoraGovernorTest {
    function testFuzz_SetsProposalDeadlineAsAdminOrTimelock(uint64 _proposalDeadline, uint256 _actorSeed) public {
        uint256 proposalId = _createValidProposal();
        vm.prank(_adminOrTimelock(_actorSeed));
        governor.setProposalDeadline(proposalId, _proposalDeadline);
        assertEq(governor.proposalDeadline(proposalId), _proposalDeadline);
    }

    function testFuzz_RevertIf_NotAdminOrTimelock(address _actor, uint64 _proposalDeadline) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        uint256 proposalId = _createValidProposal();
        vm.prank(_actor);
        vm.expectRevert(NotAdminOrTimelock.selector);
        governor.setProposalDeadline(proposalId, _proposalDeadline);
    }
}

contract SetVotingDelay is AgoraGovernorTest {
    function testFuzz_SetsVotingDelayWhenAdminOrTimelock(uint256 _votingDelay, uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        governor.setVotingDelay(_votingDelay);
        assertEq(governor.votingDelay(), _votingDelay);
    }

    function testFuzz_RevertIf_NotAdminOrTimelock(address _actor, uint256 _votingDelay) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.expectRevert(NotAdminOrTimelock.selector);
        vm.prank(_actor);
        governor.setVotingDelay(_votingDelay);
    }
}

contract SetVotingPeriod is AgoraGovernorTest {
    function testFuzz_SetsVotingPeriodAsAdminOrTimelock(uint256 _votingPeriod, uint256 _actorSeed) public {
        _votingPeriod = bound(_votingPeriod, 1, type(uint256).max);
        vm.prank(_adminOrTimelock(_actorSeed));
        governor.setVotingPeriod(_votingPeriod);
        assertEq(governor.votingPeriod(), _votingPeriod);
    }

    function testFuzz_RevertIf_NotAdminOrTimelock(address _actor, uint256 _votingPeriod) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.expectRevert(NotAdminOrTimelock.selector);
        vm.prank(_actor);
        governor.setVotingPeriod(_votingPeriod);
    }
}

contract SetProposalThreshold is AgoraGovernorTest {
    function testFuzz_SetsProposalThresholdAsAdminOrTimelock(uint256 _proposalThreshold, uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        governor.setProposalThreshold(_proposalThreshold);
        assertEq(governor.proposalThreshold(), _proposalThreshold);
    }

    function testFuzz_RevertIf_NotAdminOrTimelock(address _actor, uint256 _proposalThreshold) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.expectRevert(NotAdminOrTimelock.selector);
        vm.prank(_actor);
        governor.setProposalThreshold(_proposalThreshold);
    }
}

contract SetAdmin is AgoraGovernorTest {
    function testFuzz_SetsNewAdmin(address _newAdmin, uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        emit AdminSet(admin, _newAdmin);
        governor.setAdmin(_newAdmin);
        assertEq(governor.admin(), _newAdmin);
    }

    function testFuzz_RevertIf_NotAdmin(address _actor, address _newAdmin) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.prank(_actor);
        vm.expectRevert(NotAdminOrTimelock.selector);
        governor.setAdmin(_newAdmin);
    }
}

contract SetManager is AgoraGovernorTest {
    function testFuzz_SetsNewManager(address _newManager, uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        emit ManagerSet(manager, _newManager);
        governor.setManager(_newManager);
        assertEq(governor.manager(), _newManager);
    }

    function testFuzz_RevertIf_NotAdmin(address _actor, address _newManager) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.prank(_actor);
        vm.expectRevert(NotAdminOrTimelock.selector);
        governor.setManager(_newManager);
    }
}

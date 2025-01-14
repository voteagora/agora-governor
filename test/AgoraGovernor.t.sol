// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";

import {IHooks} from "src/interfaces/IHooks.sol";
import {AgoraGovernor} from "src/AgoraGovernor.sol";
import {AgoraGovernorMock} from "test/mocks/AgoraGovernorMock.sol";

import {MockToken} from "test/mocks/MockToken.sol";
import {Deployers} from "test/utils/Deployers.sol";

contract AgoraGovernorTest is Test, Deployers {
    // Variables
    uint256 counter;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        deployGovernor(address(0));
    }

    function executeCallback() public payable virtual {
        counter++;
    }

    function _adminOrTimelock(uint256 _actorSeed) internal view returns (address) {
        if (_actorSeed % 2 == 1) return admin;
        else return address(timelock);
    }

    function _mintAndDelegate(address _actor, uint256 _amount) public {
        vm.assume(_actor != address(0));
        vm.assume(_actor != proxyAdmin);
        vm.prank(minter);
        token.mint(_actor, _amount);
        vm.prank(_actor);
        token.delegate(_actor);
    }

    function _formatProposalData(uint256 _proposalTargetCalldata)
        public
        virtual
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");

        address[] memory targets1 = new address[](1);
        uint256[] memory values1 = new uint256[](1);
        bytes[] memory calldatas1 = new bytes[](1);
        // Call executeCallback and send 0.01 ether to receiver1
        vm.deal(address(timelock), 0.01 ether);
        targets1[0] = receiver1;
        values1[0] = 0.01 ether;
        calldatas1[0] = abi.encodeWithSelector(this.executeCallback.selector);

        address[] memory targets2 = new address[](2);
        uint256[] memory values2 = new uint256[](2);
        bytes[] memory calldatas2 = new bytes[](2);
        // Send 0.01 ether to receiver2
        targets2[0] = receiver2;
        values2[0] = 0.01 ether;
        // Call SetNumber on ExecutionTargetFake
        targets2[1] = address(this);
        calldatas2[1] = abi.encodeWithSelector(this.executeCallback.selector);

        address[] memory targets = new address[](2);
        targets[0] = targets1[0];
        targets[1] = targets2[0];
        uint256[] memory values = new uint256[](2);
        values[0] = values1[0];
        values[1] = values2[0];
        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = calldatas1[0];
        calldatas[1] = calldatas2[0];

        return (targets, values, calldatas);
    }

    // Exclude from coverage report
    function test() public virtual {}
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
    function test_queue_validInput_succeeds(address _actor) public {
        vm.assume(_actor != proxyAdmin);
        _mintAndDelegate(_actor, 1e30);

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(_actor);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 2);

        governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));

        vm.roll(block.number + 14);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));
    }

    function test_queue_manager_succeeds() public {
        _mintAndDelegate(manager, 1e30);

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 2);

        governor.castVote(proposalId, 1);

        vm.roll(block.number + 14);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));
    }

    function test_queue_notSucceeded_reverts() public {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));
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
    function test_cancel_authorized_succeeds(uint256 _actorSeed) public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        address canceller;
        if (_actorSeed % 3 == 0) canceller = admin;
        else if (_actorSeed % 3 == 1) canceller = address(timelock);
        else canceller = manager;

        vm.prank(canceller);
        governor.cancel(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }

    function test_cancel_unauthorized_reverts(address _actor) public virtual {
        vm.assume(_actor != proxyAdmin && _actor != manager && _actor != admin && _actor != address(timelock));

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        vm.prank(_actor);
        vm.expectRevert(abi.encodeWithSelector(AgoraGovernor.GovernorUnauthorizedCancel.selector));
        governor.cancel(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));
    }

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
    function test_updateTimelock_succeeds(uint256 _elapsedAfterQueuing, address _newTimelock) public {
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

    function test_updateTimelock_unauthorized_reverts(address _actor, address _newTimelock) public {
        vm.assume(_actor != governor.timelock() && _actor != proxyAdmin);
        vm.prank(_actor);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, _actor));
        governor.updateTimelock(TimelockController(payable(_newTimelock)));
    }
}

contract Quorum is AgoraGovernorTest {
    function test_quorum_succeeds(address _voter, uint208 _amount) public virtual {
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
        uint256 quorum = governor.quorum(governor.proposalSnapshot(proposalId));
        assertEq(quorum, (supply * 3) / 10);
    }
}

contract QuorumReached is AgoraGovernorTest {
    function test_quorumReached_succeeds(address _voter, address _voter2) public virtual {
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
    function test_castVote_succeeds(address _voter, address _voter2) public virtual {
        vm.assume(_voter != _voter2);
        _mintAndDelegate(_voter, 100e18);
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
    function test_castVoteWithReasonAndParams_ucceeds(address _voter) public virtual {
        _mintAndDelegate(_voter, 100e18);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _formatProposalData(0);
        uint256 snapshot = block.number + governor.votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(GovernorCountingSimple.VoteType.For), reason, params);

        assertTrue(governor.hasVoted(proposalId, _voter));
    }
}

contract VoteSucceeded is AgoraGovernorTest {
    function test_voteSucceeded_quorum_succeeds(address _voter) public virtual {
        _mintAndDelegate(_voter, 100e18);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _formatProposalData(0);
        uint256 snapshot = block.number + governor.votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(GovernorCountingSimple.VoteType.For), reason, params);

        assertTrue(governor.quorum(governor.proposalSnapshot(proposalId)) != 0);
        assertTrue(governor.quorumReached(proposalId));
        assertTrue(governor.voteSucceeded(proposalId));
    }

    function test_voteSucceeded_notSucceeded_reverts(address _voter, address _voter2) public virtual {
        vm.assume(_voter != _voter2);
        _mintAndDelegate(_voter, 100e18);
        _mintAndDelegate(_voter2, 200e18);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _formatProposalData(0);
        uint256 snapshot = block.number + governor.votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(GovernorCountingSimple.VoteType.For), reason, params);

        vm.prank(_voter2);
        governor.castVoteWithReasonAndParams(proposalId, uint8(GovernorCountingSimple.VoteType.Against), reason, "");

        assertTrue(governor.quorum(governor.proposalSnapshot(proposalId)) != 0);
        assertFalse(governor.voteSucceeded(proposalId));
    }
}

contract SetVotingDelay is AgoraGovernorTest {
    function test_setVotingDelay_succeeds(uint48 _votingDelay) public {
        vm.prank(admin);
        governor.setVotingDelay(_votingDelay);
        assertEq(governor.votingDelay(), _votingDelay);
    }

    function test_setVotingDelay_unauthorized_reverts(address _actor, uint48 _votingDelay) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.expectRevert();
        vm.prank(_actor);
        governor.setVotingDelay(_votingDelay);
    }
}

contract SetVotingPeriod is AgoraGovernorTest {
    function test_setVotingPeriod_succeeds(uint32 _votingPeriod) public {
        vm.assume(_votingPeriod > 0);
        vm.prank(admin);
        governor.setVotingPeriod(_votingPeriod);
        assertEq(governor.votingPeriod(), _votingPeriod);
    }

    function test_setVotingPeriod_unauthorized_reverts(address _actor, uint32 _votingPeriod) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.expectRevert();
        vm.prank(_actor);
        governor.setVotingPeriod(_votingPeriod);
    }
}

contract SetProposalThreshold is AgoraGovernorTest {
    function test_setProposalThreshold_succeeds(uint256 _proposalThreshold) public {
        vm.prank(admin);
        governor.setProposalThreshold(_proposalThreshold);
        assertEq(governor.proposalThreshold(), _proposalThreshold);
    }

    function test_setProposalThreshold_unauthorized_reverts(address _actor, uint256 _proposalThreshold) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.expectRevert();
        vm.prank(_actor);
        governor.setProposalThreshold(_proposalThreshold);
    }
}

contract SetAdmin is AgoraGovernorTest {
    function test_setAdmin_succeeds(address _newAdmin) public {
        vm.prank(admin);
        governor.setAdmin(_newAdmin);
        assertEq(governor.admin(), _newAdmin);
    }

    function test_setAdmin_unauthorized_reverts(address _actor, address _newAdmin) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.prank(_actor);
        vm.expectRevert();
        governor.setAdmin(_newAdmin);
    }
}

contract SetManager is AgoraGovernorTest {
    function test_setManager_succeeds(address _newManager) public {
        vm.prank(admin);
        governor.setManager(_newManager);
        assertEq(governor.manager(), _newManager);
    }

    function test_setManager_unauthorized_reverts(address _actor, address _newManager) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.prank(_actor);
        vm.expectRevert();
        governor.setManager(_newManager);
    }
}

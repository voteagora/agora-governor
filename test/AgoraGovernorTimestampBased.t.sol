/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts-v4/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable-v4/governance/utils/IVotesUpgradeable.sol";
import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable-v4/governance/IGovernorUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts-v4/proxy/ERC1967/ERC1967Proxy.sol";
import {Timelock, TimelockControllerUpgradeable} from "test/mocks/TimelockMock.sol";
import {L2GovToken} from "ERC20VotesPartialDelegationUpgradeable/L2GovToken.sol";
import {VotingModule} from "src/modules/VotingModule.sol";
import {ProposalTypesConfigurator, IProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {
    ApprovalVotingModule,
    ProposalOption,
    ProposalSettings,
    PassingCriteria
} from "src/modules/ApprovalVotingModule.sol";
import {OptimisticModule, ProposalSettings as OptimisticProposalSettings} from "src/modules/OptimisticModule.sol";
import {AgoraGovernorMock, AgoraGovernor} from "test/mocks/AgoraGovernorMock.sol";
import {ApprovalVotingModuleMock} from "test/mocks/ApprovalVotingModuleMock.sol";
import {VoteType} from "test/ApprovalVotingModule.t.sol";
import {ExecutionTargetFake} from "test/fakes/ExecutionTargetFake.sol";
import {IVotingToken} from "src/interfaces/IVotingToken.sol";

enum ProposalState {
    Pending,
    Active,
    Canceled,
    Defeated,
    Succeeded,
    Queued,
    Expired,
    Executed
}

contract AgoraGovernorTimestampBasedTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 startBlock,
        uint256 endBlock,
        string description,
        uint8 proposalType
    );
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address indexed votingModule,
        bytes proposalData,
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 startBlock,
        uint256 endBlock,
        string description,
        uint8 proposalType
    );

    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address votingModule,
        bytes proposalData,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    event VoteCastWithParams(
        address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason, bytes params
    );

    event ProposalCanceled(uint256 proposalId);
    event ProposalExecuted(uint256 proposalId);
    event ProposalTypeUpdated(uint256 indexed proposalId, uint8 proposalType);
    event AdminSet(address indexed oldAdmin, address indexed newAdmin);
    event ManagerSet(address indexed oldManager, address indexed newManager);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidProposalType(uint8 proposalType);
    error InvalidProposalId();
    error InvalidProposedTxForType();
    error InvalidProposalLength();
    error InvalidEmptyProposal();
    error InvalidVotesBelowThreshold();
    error InvalidProposalExists();
    error NotAdminOrTimelock();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address deployer = makeAddr("deployer");
    ProposalTypesConfigurator public proposalTypesConfigurator;
    Timelock public timelock;
    ExecutionTargetFake public targetFake;
    address internal admin = makeAddr("admin");
    address internal proxyAdmin = makeAddr("proxyAdmin");
    address internal manager = makeAddr("manager");
    address internal minter = makeAddr("minter");
    string description = "a nice description";
    // helper to keep track of proposal types
    uint256 proposalTypesIndex = 1;
    uint256 timelockDelay;

    L2GovToken internal govToken;
    address public implementation;
    address internal governorProxy;
    AgoraGovernorMock public governor;
    ApprovalVotingModuleMock internal module;
    OptimisticModule internal optimisticModule;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        vm.startPrank(deployer);

        // Deploy token
        govToken = L2GovToken(
            address(
                new ERC1967Proxy(
                    address(new L2GovToken()), abi.encodeCall(govToken.initialize, (admin, "L2 Gov Token", "gL2"))
                )
            )
        );

        // Deploy timelock
        timelock = Timelock(payable(new TransparentUpgradeableProxy(address(new Timelock()), proxyAdmin, "")));

        // Deploy governor impl
        implementation = address(new AgoraGovernorMock());

        // Deploy Proposal Types Configurator
        proposalTypesConfigurator = new ProposalTypesConfigurator(
            vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1),
            new IProposalTypesConfigurator.ProposalType[](0)
        );

        // Deploy governor proxy
        governorProxy = address(
            new TransparentUpgradeableProxy(
                implementation,
                proxyAdmin,
                abi.encodeCall(
                    AgoraGovernor.initialize,
                    (
                        IVotingToken(address(govToken)),
                        AgoraGovernor.SupplyType.Total,
                        admin,
                        manager,
                        timelock,
                        IProposalTypesConfigurator(proposalTypesConfigurator)
                    )
                )
            )
        );
        governor = AgoraGovernorMock(payable(governorProxy));

        // Initialize timelock
        timelockDelay = 2 days;
        timelock.initialize(timelockDelay, governorProxy, admin);
        vm.stopPrank();

        // Deploy modules
        module = new ApprovalVotingModuleMock(address(governor));
        optimisticModule = new OptimisticModule(address(governor));

        // do admin stuff
        vm.startPrank(admin);
        govToken.grantRole(govToken.MINTER_ROLE(), minter);
        governor.setModuleApproval(address(module), true);
        governor.setModuleApproval(address(optimisticModule), true);
        governor.setVotingDelayInSeconds(3 days);
        governor.setVotingPeriodInSeconds(7 days);
        proposalTypesConfigurator.setProposalType(0, 3_000, 5_000, "Default", "Lorem Ipsum", address(0));
        proposalTypesConfigurator.setProposalType(1, 5_000, 7_000, "Alt", "Lorem Ipsum", address(module));
        proposalTypesConfigurator.setProposalType(2, 0, 0, "Optimistic", "Lorem Ipsum", address(optimisticModule));
        vm.stopPrank();
        targetFake = new ExecutionTargetFake();

        vm.warp(1);
    }

    /**
     * @notice Generates the scope key defined as the contract address combined with the function selector
     * @param contractAddress Address of the contract to be enforced by the scope
     * @param selector A byte4 function selector on the contract to be enforced by the scope
     */
    function _pack(address contractAddress, bytes4 selector) internal pure returns (bytes24 result) {
        bytes20 left = bytes20(contractAddress);
        assembly ("memory-safe") {
            left := and(left, shl(96, not(0)))
            selector := and(selector, shl(224, not(0)))
            result := or(left, shr(160, selector))
        }
    }

    function _formatProposalData(uint256 _proposalTargetCalldata) public virtual returns (bytes memory proposalData) {
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
        targets2[1] = address(targetFake);
        calldatas2[1] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        ProposalOption[] memory options = new ProposalOption[](2);
        options[0] = ProposalOption(0, targets1, values1, calldatas1, "option 1");
        options[1] = ProposalOption(0, targets2, values2, calldatas2, "option 2");
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 1,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 1,
            budgetToken: address(0),
            budgetAmount: 1 ether
        });

        return abi.encode(options, settings);
    }

    function executeCallback() public payable virtual {}

    function _assumeZeroBalance(address _actor) public view {
        vm.assume(_actor != address(module));
    }

    function _mintAndDelegate(address _actor, uint256 _amount) internal {
        vm.assume(_actor != address(0));
        vm.assume(_actor != proxyAdmin);
        vm.prank(minter);
        govToken.mint(_actor, _amount);
        vm.prank(_actor);
        govToken.delegate(_actor);
    }

    function _adminOrTimelock(uint256 _actorSeed) internal returns (address) {
        if (_actorSeed % 2 == 1) return admin;
        else return governor.timelock();
    }

    function _createValidProposal() internal returns (uint256) {
        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();
        // ProposalThreshold is not set, so it defaults to 0.
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        return proposalId;
    }
}

contract ProposeTimestampBased is AgoraGovernorTimestampBasedTest {
    function testFuzz_CreatesProposalWhenThresholdIsMet(
        address _actor,
        uint256 _proposalThreshold,
        uint256 _actorBalance
    ) public virtual {
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
        govToken.mint(_actor, _actorBalance);
        vm.startPrank(_actor);
        govToken.delegate(_actor);
        vm.roll(vm.getBlockNumber() + 1);

        uint256 proposalId;
        proposalId = governor.propose(targets, values, calldatas, "Test", 0);
        vm.stopPrank();
        assertGt(governor.proposalSnapshot(proposalId), 0);
        assertGt(governor.proposalStartTimestamp(proposalId), 0);
    }

    function testFuzz_CreatesProposalAsManager(uint256 _proposalThreshold) public virtual {
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
        proposalId = governor.propose(targets, values, calldatas, "Test", 0);
        assertGt(governor.proposalSnapshot(proposalId), 0);
        assertGt(governor.proposalStartTimestamp(proposalId), 0);
    }

    function testRevert_WithType_InvalidProposalType() public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);
        uint8 invalidPropType = 3;

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(InvalidProposalType.selector, invalidPropType));
        governor.propose(targets, values, calldatas, "Test", invalidPropType);
    }

    function testFuzz_RevertIf_ThresholdNotMet(
        address _actor,
        uint256 _proposalThreshold,
        uint256 _actorBalance,
        uint8 _proposalType
    ) public virtual {
        vm.assume(_actor != manager && _actor != address(0) && _actor != proxyAdmin);
        _assumeZeroBalance(_actor);
        _proposalThreshold = bound(_proposalThreshold, 1, type(uint208).max);
        _actorBalance = bound(_actorBalance, 0, _proposalThreshold - 1);
        _proposalType = uint8(bound(_proposalType, 0, proposalTypesIndex));
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(admin);
        governor.setProposalThreshold(_proposalThreshold);

        // Give actor some tokens, but not enough to meet proposal threshold
        vm.prank(minter);
        govToken.mint(_actor, _actorBalance);
        vm.startPrank(_actor);
        govToken.delegate(_actor);
        vm.roll(vm.getBlockNumber() + 1);
        vm.expectRevert(InvalidVotesBelowThreshold.selector);
        if (_proposalType > 0) {
            governor.propose(targets, values, calldatas, "Test");
        } else {
            governor.propose(targets, values, calldatas, "Test", _proposalType);
        }
    }

    function testRevert_proposalAlreadyCreated() public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(manager);
        governor.propose(targets, values, calldatas, "Test", 0);

        vm.expectRevert(InvalidProposalExists.selector);
        governor.propose(targets, values, calldatas, "Test", 0);
        vm.stopPrank();
    }
}

contract QueueTimestampBased is AgoraGovernorTimestampBasedTest {
    // TODO: test that non-passing proposals can't be queued (aka voting period over)
    function testFuzz_QueuesASucceedingProposalWhenManager(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        uint256 startTimestamp = block.timestamp;

        vm.roll(block.number + 1);
        vm.warp(startTimestamp + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        vm.warp(startTimestamp + 15);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Succeeded));
        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));
    }

    function testFuzz_QueuesASucceededProposal(
        address _actor,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.assume(_actor != proxyAdmin);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        uint256 startTimestamp = block.timestamp;

        vm.roll(block.number + 1);
        vm.warp(startTimestamp + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        vm.warp(startTimestamp + 15);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Succeeded));
        vm.prank(_actor);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));
    }

    function testFuzz_RevertIf_QueuesAProposalBeforeItSucceeds(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Pending));
        vm.prank(manager);
        vm.expectRevert("Governor: proposal not successful");
        governor.queue(targets, values, calldatas, keccak256("Test"));
    }

    function testFuzz_RevertIf_ProposalAlreadyQueued(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing)
        public
    {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        uint256 startTimestamp = block.timestamp;

        vm.roll(block.number + 1);
        vm.warp(startTimestamp + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        vm.warp(startTimestamp + 15);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Succeeded));
        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));

        vm.prank(manager);
        vm.expectRevert("Governor: proposal not successful");
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));
    }
}

contract ExecuteTimestampBased is AgoraGovernorTimestampBasedTest {
    function testFuzz_ExecutesAProposalWhenManager(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing)
        public
        virtual
    {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        uint256 startTimestamp = block.timestamp;

        vm.roll(block.number + 1);
        vm.warp(startTimestamp + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        vm.warp(startTimestamp + 15);

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Executed));
        assertEq(targetFake.number(), _proposalTargetCalldata);
    }

    function testFuzz_ExecutesAProposalAsAnyUser(
        address _actor,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public virtual {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.assume(_actor != proxyAdmin);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        uint256 startTimestamp = block.timestamp;

        vm.roll(block.number + 1);
        vm.warp(startTimestamp + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        vm.warp(startTimestamp + 15);

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(_actor);
        governor.execute(targets, values, calldatas, keccak256("Test"));

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Executed));
        assertEq(targetFake.number(), _proposalTargetCalldata);
    }

    function testFuzz_RevertIf_ProposalNotQueued(uint256 _proposalTargetCalldata) public {
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        uint256 startTimestamp = block.timestamp;

        vm.roll(block.number + 1);
        vm.warp(startTimestamp + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        vm.warp(startTimestamp + 15);

        vm.expectRevert("Governor: proposal not queued");
        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));
    }

    function testFuzz_RevertIf_ProposalQueuedButNotReady(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing)
        public
    {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, 0, timelock.getMinDelay() - 1);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        uint256 startTimestamp = block.timestamp;

        vm.roll(block.number + 1);
        vm.warp(startTimestamp + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        vm.warp(startTimestamp + 15);

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.expectRevert("TimelockController: operation is not ready");
        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));
    }

    function testFuzz_RevertIf_ProposalNotSuccessful(uint256 _proposalTargetCalldata) public {
        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();

        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 15);

        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Defeated));

        vm.prank(manager);
        vm.expectRevert("Governor: proposal not queued");
        governor.execute(targets, values, calldatas, keccak256("Test"));
    }

    function testFuzz_RevertIf_ProposalAlreadyExecuted(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing)
        public
    {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        uint256 startTimestamp = block.timestamp;

        vm.roll(block.number + 1);
        vm.warp(startTimestamp + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        vm.warp(startTimestamp + 15);

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));

        vm.expectRevert("Governor: proposal not queued");
        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));
    }
}

contract CancelTimestampBased is AgoraGovernorTimestampBasedTest {
    function testFuzz_CancelProposalAfterSucceedingButBeforeQueuing(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing,
        uint256 _actorSeed
    ) public virtual {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        uint256 startTimestamp = block.timestamp;

        vm.roll(block.number + 1);
        vm.warp(startTimestamp + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        vm.warp(startTimestamp + 15);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Succeeded));

        vm.expectEmit();
        emit ProposalCanceled(proposalId);
        vm.prank(_adminOrTimelock(_actorSeed));
        governor.cancel(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
    }

    function testFuzz_CancelProposalAfterQueuing(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing,
        uint256 _actorSeed
    ) public virtual {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        uint256 startTimestamp = block.timestamp;

        vm.roll(block.number + 1);
        vm.warp(startTimestamp + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        vm.warp(startTimestamp + 15);

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));
        vm.expectEmit();
        emit ProposalCanceled(proposalId);
        vm.prank(_adminOrTimelock(_actorSeed));
        governor.cancel(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
    }

    function test_CancelsProposalBeforeVoteEnd(uint256 _actorSeed) public virtual {
        vm.prank(minter);
        govToken.mint(address(this), 1000);
        govToken.delegate(address(this));

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);

        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        vm.stopPrank();

        vm.expectEmit();
        emit ProposalCanceled(proposalId);
        vm.prank(_adminOrTimelock(_actorSeed));
        governor.cancel(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
    }

    function testFuzz_RevertIf_CancelProposalAfterExecution(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing,
        uint256 _actorSeed
    ) public virtual {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        uint256 startTimestamp = block.timestamp;

        vm.roll(block.number + 1);
        vm.warp(startTimestamp + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        vm.warp(startTimestamp + 15);

        vm.startPrank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);
        governor.execute(targets, values, calldatas, keccak256("Test"));
        vm.stopPrank();

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Executed));
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectRevert("Governor: proposal not active");
        governor.cancel(targets, values, calldatas, keccak256("Test"));
    }

    function test_RevertIf_ProposalDoesntExist(uint256 _actorSeed) public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectRevert("Governor: unknown proposal id");
        governor.cancel(targets, values, calldatas, keccak256("Test"));
    }
}

contract UpdateTimelockTimestampBased is AgoraGovernorTimestampBasedTest {
    function testFuzz_UpdateTimelock(uint256 _elapsedAfterQueuing, address _newTimelock) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(governor);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(governor.updateTimelock.selector, address(_newTimelock));

        vm.startPrank(admin);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(type(uint32).max);
        governor.setVotingDelayInSeconds(0);
        governor.setVotingPeriodInSeconds(14);
        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        uint256 startTimestamp = block.timestamp;

        vm.roll(block.number + 1);
        vm.warp(startTimestamp + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 10);
        vm.warp(startTimestamp + 15);

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

contract SetProposalDeadlineTimestamp is AgoraGovernorTimestampBasedTest {
    function testFuzz_SetsProposalDeadlineTimestampAsAdminOrTimelock(uint64 _proposalDeadline, uint256 _actorSeed)
        public
    {
        uint256 proposalId = _createValidProposal();
        vm.prank(_adminOrTimelock(_actorSeed));
        governor.setProposalDeadlineTimestamp(proposalId, _proposalDeadline);
        assertEq(governor.proposalDeadlineTimestamp(proposalId), _proposalDeadline);
    }

    function testFuzz_RevertIf_NotAdminOrTimelock(address _actor, uint64 _proposalDeadline) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        uint256 proposalId = _createValidProposal();
        vm.prank(_actor);
        vm.expectRevert(NotAdminOrTimelock.selector);
        governor.setProposalDeadlineTimestamp(proposalId, _proposalDeadline);
    }
}

contract SetVotingDelayInSeconds is AgoraGovernorTimestampBasedTest {
    function testFuzz_SetsVotingDelayWhenAdminOrTimelock(uint256 _votingDelay, uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        governor.setVotingDelayInSeconds(_votingDelay);
        assertEq(governor.votingDelayInSeconds(), _votingDelay);
    }

    function testFuzz_RevertIf_NotAdminOrTimelock(address _actor, uint256 _votingDelay) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.expectRevert(NotAdminOrTimelock.selector);
        vm.prank(_actor);
        governor.setVotingDelayInSeconds(_votingDelay);
    }
}

contract SetVotingPeriodInSeconds is AgoraGovernorTimestampBasedTest {
    function testFuzz_SetsVotingPeriodAsAdminOrTimelock(uint256 _votingPeriod, uint256 _actorSeed) public {
        _votingPeriod = bound(_votingPeriod, 1, type(uint256).max);
        vm.prank(_adminOrTimelock(_actorSeed));
        governor.setVotingPeriodInSeconds(_votingPeriod);
        assertEq(governor.votingPeriodInSeconds(), _votingPeriod);
    }

    function testFuzz_RevertIf_NotAdminOrTimelock(address _actor, uint256 _votingPeriod) public {
        vm.assume(_actor != admin && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.expectRevert(NotAdminOrTimelock.selector);
        vm.prank(_actor);
        governor.setVotingPeriodInSeconds(_votingPeriod);
    }
}

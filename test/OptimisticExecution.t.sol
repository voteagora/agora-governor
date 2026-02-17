// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts-v4/token/ERC20/IERC20.sol";
import {TokenMock} from "test/mocks/TokenMock.sol";
import {OptimisticExecution, Proposal, ProposalSettings} from "src/modules/OptimisticExecution.sol";
import {VotingModule} from "src/modules/VotingModule.sol";
import {OptimisticExecutionMock} from "test/mocks/OptimisticExecutionMock.sol";
import {ProposalTypesConfigurator, IProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {Timelock, TimelockControllerUpgradeable} from "test/mocks/TimelockMock.sol";
import {ExecutionTargetFake} from "test/fakes/ExecutionTargetFake.sol";
import {L2GovToken} from "ERC20VotesPartialDelegationUpgradeable/L2GovToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts-v4/proxy/ERC1967/ERC1967Proxy.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts-v4/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AgoraGovernorMock, AgoraGovernor} from "test/mocks/AgoraGovernorMock.sol";
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

enum VoteType {
    Against,
    For,
    Abstain
}

contract OptimisticExecutionModuleTest is Test {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address internal token = address(new TokenMock(address(this)));
    string internal description = "a nice description";
    bytes32 internal descriptionHash = keccak256(bytes("a nice description"));
    AgoraGovernorMock public governor;
    address internal voter = makeAddr("voter");
    address internal altVoter = makeAddr("altVoter");
    address receiver1 = makeAddr("receiver1");
    address receiver2 = makeAddr("receiver2");

    address deployer = makeAddr("deployer");
    ProposalTypesConfigurator public proposalTypesConfigurator;
    Timelock public timelock;
    ExecutionTargetFake public targetFake;
    address internal admin = makeAddr("admin");
    address internal proxyAdmin = makeAddr("proxyAdmin");
    address internal manager = makeAddr("manager");
    address internal minter = makeAddr("minter");
    // helper to keep track of proposal types
    uint256 proposalTypesIndex = 1;
    uint256 timelockDelay;

    L2GovToken internal govToken;
    address public implementation;
    address internal governorProxy;
    OptimisticExecutionMock internal module;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
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
        module = new OptimisticExecutionMock(address(governor));

        // do admin stuff
        vm.startPrank(admin);
        govToken.grantRole(govToken.MINTER_ROLE(), minter);
        governor.setModuleApproval(address(module), true);
        proposalTypesConfigurator.setProposalType(1, 0, 0, "Optimistic", "Lorem Ipsum", address(module));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testPropose() public {
        (
            bytes memory proposalData,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ProposalSettings memory settings
        ) = _formatProposalData();

        vm.prank(address(governor));
        uint256 proposalId = hashProposalWithModule(address(governor), address(module), proposalData, descriptionHash);
        module.propose(proposalId, proposalData, descriptionHash);

        Proposal memory proposal = module._proposals(proposalId);

        assertEq(proposal.settings.againstThreshold, settings.againstThreshold);
        assertEq(proposal.settings.isRelativeToVotableSupply, settings.isRelativeToVotableSupply);
    }

    function testCountVote_voteForSingle() public {
        (
            bytes memory proposalData,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ProposalSettings memory settings
        ) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(address(governor), address(module), proposalData, descriptionHash);
        uint256 weight = 100;

        vm.startPrank(address(governor));
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 0;
        bytes memory params = abi.encode(votes);

        Proposal memory proposal = module._proposals(proposalId);
    }

    function testVoteSucceeded() public {
        (
            bytes memory proposalData,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ProposalSettings memory settings
        ) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(address(governor), address(module), proposalData, descriptionHash);
        uint256 weight = 100;

        vm.startPrank(address(governor));
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](1);
        bytes memory params = abi.encode(votes);

        module._countVote(proposalId, voter, uint8(VoteType.For), weight, params);

        assertTrue(module._voteSucceeded(proposalId));
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_propose_existingProposal() public {
        (
            bytes memory proposalData,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ProposalSettings memory settings
        ) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(address(governor), address(module), proposalData, descriptionHash);
        vm.prank(address(governor));
        module.propose(proposalId, proposalData, descriptionHash);

        vm.expectRevert(VotingModule.ExistingProposal.selector);
        vm.prank(address(governor));
        module.propose(proposalId, proposalData, descriptionHash);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _formatProposalData()
        internal
        view
        returns (
            bytes memory proposalData,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ProposalSettings memory settings
        )
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        // Send 0.01 ether to receiver1
        targets[0] = receiver1;
        values[0] = 0.6 ether;
        calldatas[0] = abi.encodeCall(IERC20.transfer, (receiver1, 0.6 ether));

        settings = ProposalSettings({againstThreshold: 10, isRelativeToVotableSupply: true});

        proposalData = abi.encode(targets, values, calldatas, settings);
    }

    function hashProposalWithModule(
        address sender,
        address module_,
        bytes memory proposalData,
        bytes32 descriptionHash_
    ) public view virtual returns (uint256) {
        return uint256(keccak256(abi.encode(sender, module_, proposalData, descriptionHash_)));
    }
}

contract GovernorMock {
    function timelock() external view returns (address) {
        return address(this);
    }
}

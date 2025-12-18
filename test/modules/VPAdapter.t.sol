// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";

import {Hooks} from "src/libraries/Hooks.sol";
import {VPAdapter, Proposal} from "src/modules/VPAdapter.sol";
import {OptimisticModule} from "src/modules/OptimisticModule.sol";
import {Middleware} from "src/Middleware.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {MockToken} from "test/mocks/MockToken.sol";
import {Deployers} from "test/utils/Deployers.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Merkle} from "@murky/Merkle.sol";

enum VoteType {
    Against,
    For,
    Abstain
}

contract VPAdapterTest is Test, Deployers {
    VPAdapter module;
    OptimisticModule optimistic;
    Middleware middleware;
    string description = "my description is this one#proposalTypeId=1#proposalData=";
    address voter1 = makeAddr("voter1");
    address voter2 = makeAddr("voter2");
    address test = makeAddr("test");
    bytes32[] data = new bytes32[](2);

    Merkle internal merkle;
    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        module = VPAdapter(
            address(uint160(Hooks.BEFORE_VOTE_SUCCEEDED_FLAG | Hooks.AFTER_PROPOSE_FLAG | Hooks.BEFORE_VOTE_FLAG))
        );

        optimistic = OptimisticModule(
            address(uint160(Hooks.BEFORE_VOTE_SUCCEEDED_FLAG | Hooks.AFTER_PROPOSE_FLAG | Hooks.BEFORE_QUEUE_FLAG))
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
            "src/modules/VPAdapter.sol:VPAdapter", abi.encode(address(governor), address(admin)), address(module)
        );

        deployCodeTo(
            "src/modules/OptimisticModule.sol:OptimisticModule",
            abi.encode(address(governor), address(middleware)),
            address(optimistic)
        );

        vm.startPrank(admin);
        middleware.setProposalType(1, 0, 0, "Alt", "Lorem Ipsum", address(module));
        middleware.setProposalType(2, 0, 0, "Alt", "Lorem Ipsum", address(optimistic));

        merkle = new Merkle();

        data[0] = keccak256(bytes.concat(keccak256(abi.encode(address(voter1), 1000))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(address(voter2), 2000))));

        VPAdapter(module).setQuorum(3000);

        vm.stopPrank();
    }

    function createProposal() internal returns (uint256 proposalId) {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (test, 100));
        targets[1] = test;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        governor.setProposalThreshold(0);
        proposalId = governor.propose(targets, values, calldatas, description);
        bytes32 root = merkle.getRoot(data);

        VPAdapter(module).setMerkleRoot(root);
        vm.stopPrank();
    }

    function test_createProposal() public {
        uint256 proposalId = createProposal();

        (address _governor, uint256 _quorum, bytes32 _root, uint256 _expectedBlock, uint256 _startBlock) = VPAdapter(module).proposals(proposalId);

        assertEq(_quorum, 3000);
        assertEq(_root, bytes32(0));
        assertEq(_governor, address(governor));
    }

    function test_CastVoteWithMerkleProof() public {
        uint256 proposalId = createProposal();

        uint256 challengePeriod = (block.number + (votingDelay / 2));
        vm.roll(challengePeriod);

        bytes32 root = merkle.getRoot(data);
        vm.prank(admin);
        VPAdapter(module).setMerkleRoot(root);

        vm.roll(challengePeriod + (votingDelay / 2) + 1);

        bytes32[] memory proof = merkle.getProof(data, 0);
        bytes memory params = abi.encode(1000, proof);

        vm.startPrank(voter1);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 1000);
        assertEq(againstVotes, 0);
        assertEq(abstainVotes, 0);

        vm.stopPrank();
    }

    function testVoteSucceeded() public {
        uint256 proposalId = createProposal();
        uint256 challengePeriod = (block.number + (votingDelay / 2));
        vm.roll(challengePeriod);

        bytes32 root = merkle.getRoot(data);
        vm.prank(admin);
        VPAdapter(module).setMerkleRoot(root);

        vm.roll(challengePeriod + (votingDelay / 2) + 1);

        bytes32[] memory proof1 = merkle.getProof(data, 0);
        bytes memory params1 = abi.encode(1000, proof1);

        vm.startPrank(voter1);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params1);
        vm.stopPrank();

        vm.startPrank(voter2);
        bytes32[] memory proof2 = merkle.getProof(data, 1);
        bytes memory params2 = abi.encode(2000, proof2);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params2);
        vm.stopPrank();

        assertTrue(governor.voteSucceeded(proposalId));
    }

    function testVoteFailsQuorum() public {
        uint256 proposalId = createProposal();
        uint256 challengePeriod = (block.number + (votingDelay / 2));
        vm.roll(challengePeriod);

        bytes32 root = merkle.getRoot(data);
        vm.prank(admin);
        VPAdapter(module).setMerkleRoot(root);

        vm.roll(challengePeriod + (votingDelay / 2) + 1);

        bytes32[] memory proof = merkle.getProof(data, 0);
        bytes memory params = abi.encode(1000, proof);

        vm.startPrank(voter1);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), "a good reason", params);
        vm.stopPrank();

        vm.roll(block.number + votingPeriod);
        assertFalse(governor.voteSucceeded(proposalId));
    }

    function testUseMerkleThreshold() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (test, 100));
        targets[1] = test;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        //voter 1 balance
        governor.setProposalThreshold(1000);
        vm.stopPrank();

        bytes memory proposalData;

        bytes32[] memory proof = merkle.getProof(data, 0);
        uint256 voter1Weight = 1000;
        proposalData = abi.encode(voter1Weight, proof);

        string memory descriptionWithData = string.concat(description, string(proposalData));

        bytes32 root = merkle.getRoot(data);
        vm.prank(admin);
        VPAdapter(module).setMerkleRoot(root);

        vm.prank(voter1);
        governor.propose(targets, values, calldatas, descriptionWithData);
    }

    function testUseMerkleThresholdRevertInvalidProof() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (test, 100));
        targets[1] = test;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        //voter 1 balance
        governor.setProposalThreshold(1000);
        vm.stopPrank();

        bytes memory proposalData;

        bytes32[] memory proof = merkle.getProof(data, 1); //use voter2 proof data
        uint256 voter1Weight = 1000;
        proposalData = abi.encode(voter1Weight, proof);

        string memory descriptionWithData = string.concat(description, string(proposalData));

        bytes32 root = merkle.getRoot(data);
        vm.prank(admin);
        VPAdapter(module).setMerkleRoot(root);

        vm.prank(voter1);
        vm.expectRevert("invalid proof");
        governor.propose(targets, values, calldatas, descriptionWithData);
    }

    function testUseMerkleThresholdNotMetRevert() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (test, 100));
        targets[1] = test;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        //voter 1 balance
        governor.setProposalThreshold(2000);
        uint256 _proposalThreshold = governor.proposalThreshold();
        vm.stopPrank();

        bytes memory proposalData;

        bytes32[] memory proof = merkle.getProof(data, 0);
        uint256 voter1Weight = 1000;
        proposalData = abi.encode(voter1Weight, proof);

        string memory descriptionWithData = string.concat(description, string(proposalData));

        bytes32 root = merkle.getRoot(data);
        vm.prank(admin);
        VPAdapter(module).setMerkleRoot(root);

        vm.prank(voter1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorInsufficientProposerVotes.selector, voter1, voter1Weight, _proposalThreshold
            )
        );
        governor.propose(targets, values, calldatas, descriptionWithData);
    }

    function testUseMerkleThresholdWrongModule() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(IERC20.transfer, (test, 100));
        targets[1] = test;
        values[1] = 0.2 ether;
        calldatas[1] = calldatas[0];

        vm.startPrank(admin);
        //voter 1 balance
        governor.setProposalThreshold(2000);
        uint256 _proposalThreshold = governor.proposalThreshold();
        vm.stopPrank();

        bytes memory proposalData;

        bytes32[] memory proof = merkle.getProof(data, 0);
        uint256 voter1Weight = 1000;
        proposalData = abi.encode(voter1Weight, proof);

        // Use a module that does not support merkle voting
        string memory description2 = "my description for optimistic#proposalTypeId=2#proposalData=";

        string memory descriptionWithData = string.concat(description2, string(proposalData));

        bytes32 root = merkle.getRoot(data);
        vm.prank(admin);
        VPAdapter(module).setMerkleRoot(root);

        vm.prank(voter1);
        vm.expectRevert(
            abi.encodeWithSelector(IGovernor.GovernorInsufficientProposerVotes.selector, voter1, 0, _proposalThreshold)
        );
        governor.propose(targets, values, calldatas, descriptionWithData);
    }
}

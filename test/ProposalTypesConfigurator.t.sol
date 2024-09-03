// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";

contract ProposalTypesConfiguratorTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalTypeSet(
        uint8 indexed proposalTypeId, uint16 quorum, uint16 approvalThreshold, string name, string description, bytes32[] txTypeHashes
    );

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    address admin = makeAddr("admin");
    address timelock = makeAddr("timelock");
    address manager = makeAddr("manager");
    address deployer = makeAddr("deployer");
    GovernorMock public governor;
    ProposalTypesConfigurator public proposalTypesConfigurator;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        governor = new GovernorMock(admin, timelock);

        vm.startPrank(deployer);
        proposalTypesConfigurator = new ProposalTypesConfigurator();
        proposalTypesConfigurator.initialize(address(governor), new ProposalTypesConfigurator.ProposalType[](0));
        vm.stopPrank();

        vm.startPrank(admin);
        bytes32[] memory transactions = new bytes32[](1);
        proposalTypesConfigurator.setProposalType(0, 3_000, 5_000, "Default", "Lorem Ipsum", address(0), transactions);
        proposalTypesConfigurator.setProposalType(1, 5_000, 7_000, "Alt", "Lorem Ipsum", address(0), transactions);

        // Setup Scope logic
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address _from = makeAddr("from");
        address _to = makeAddr("to");
        bytes memory txEncoded = abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(10));

        bytes[] memory parameters = new bytes[](3);
        parameters[0] = abi.encode(uint256(uint160(_from)));
        parameters[1] = abi.encode(uint256(uint160(_to)));
        parameters[2] = abi.encode(uint256(10));

        IProposalTypesConfigurator.Comparators[] memory comparators = new IProposalTypesConfigurator.Comparators[](3);

        comparators[0] = IProposalTypesConfigurator.Comparators(1); // EQ
        comparators[1] = IProposalTypesConfigurator.Comparators(1); // EQ
        comparators[2] = IProposalTypesConfigurator.Comparators(3); // GREATER THAN

        proposalTypesConfigurator.setScopeForProposalType(0, txTypeHash, txEncoded, parameters, comparators);
        vm.stopPrank();
    }

    function _adminOrTimelock(uint256 _actorSeed) internal view returns (address) {
        if (_actorSeed % 2 == 1) return admin;
        else return governor.timelock();
    }
}

contract Initialize is ProposalTypesConfiguratorTest {
    function test_SetsGovernor(address _actor, address _governor) public {
        ProposalTypesConfigurator proposalTypesConfigurator = new ProposalTypesConfigurator();
        vm.prank(_actor);
        proposalTypesConfigurator.initialize(address(_governor), new ProposalTypesConfigurator.ProposalType[](0));
        assertEq(_governor, address(proposalTypesConfigurator.governor()));
    }

    function test_SetsProposalTypes(address _actor, uint8 _proposalTypes) public {
        ProposalTypesConfigurator proposalTypesConfigurator = new ProposalTypesConfigurator();
        ProposalTypesConfigurator.ProposalType[] memory proposalTypes =
            new ProposalTypesConfigurator.ProposalType[](_proposalTypes);
        vm.prank(_actor);
        proposalTypesConfigurator.initialize(address(governor), proposalTypes);
        for (uint8 i = 0; i < _proposalTypes; i++) {
            IProposalTypesConfigurator.ProposalType memory propType = proposalTypesConfigurator.proposalTypes(i);
            assertEq(propType.quorum, 0);
            assertEq(propType.approvalThreshold, 0);
            assertEq(propType.name, "");
        }
    }

    function test_RevertIf_AlreadyInit() public {
        vm.expectRevert(IProposalTypesConfigurator.AlreadyInit.selector);
        proposalTypesConfigurator.initialize(address(governor), new ProposalTypesConfigurator.ProposalType[](0));
    }
}

contract ProposalTypes is ProposalTypesConfiguratorTest {
    function test_ProposalTypes() public view {
        IProposalTypesConfigurator.ProposalType memory propType = proposalTypesConfigurator.proposalTypes(0);

        assertEq(propType.quorum, 3_000);
        assertEq(propType.approvalThreshold, 5_000);
        assertEq(propType.name, "Default");
    }
}

contract SetProposalType is ProposalTypesConfiguratorTest {
    function testFuzz_SetProposalType(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        bytes32[] memory transactions = new bytes32[](1);
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", transactions);
        proposalTypesConfigurator.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0), transactions);

        IProposalTypesConfigurator.ProposalType memory propType = proposalTypesConfigurator.proposalTypes(0);

        assertEq(propType.quorum, 4_000);
        assertEq(propType.approvalThreshold, 6_000);
        assertEq(propType.name, "New Default");
        assertEq(propType.description, "Lorem Ipsum");
        assertEq(propType.txTypeHashes, transactions);

        vm.prank(_adminOrTimelock(_actorSeed));
        proposalTypesConfigurator.setProposalType(1, 0, 0, "Optimistic", "Lorem Ipsum", address(0), transactions);
        propType = proposalTypesConfigurator.proposalTypes(1);
        assertEq(propType.quorum, 0);
        assertEq(propType.approvalThreshold, 0);
        assertEq(propType.name, "Optimistic");
        assertEq(propType.description, "Lorem Ipsum");
        assertEq(propType.txTypeHashes, transactions);
    }

    function testFuzz_SetScopeForProposalType(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        bytes32[] memory transactions = new bytes32[](1);
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", transactions);
        proposalTypesConfigurator.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0), transactions);

        vm.prank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);
        bytes[] memory parameters = new bytes[](1);
        IProposalTypesConfigurator.Comparators[] memory comparators = new IProposalTypesConfigurator.Comparators[](1);

        proposalTypesConfigurator.setScopeForProposalType(0, txTypeHash, txEncoded, parameters, comparators);

        bytes memory limit = proposalTypesConfigurator.getLimit(0, txTypeHash);
        assertEq(limit, txEncoded);
    }

    function test_RevertIf_NotAdminOrTimelock(address _actor) public {
        vm.assume(_actor != admin && _actor != GovernorMock(governor).timelock());
        vm.expectRevert(IProposalTypesConfigurator.NotAdminOrTimelock.selector);
        proposalTypesConfigurator.setProposalType(0, 0, 0, "", "Lorem Ipsum", address(0), new bytes32[](1));
    }

    function test_RevertIf_setProposalType_InvalidQuorum(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectRevert(IProposalTypesConfigurator.InvalidQuorum.selector);
        proposalTypesConfigurator.setProposalType(0, 10_001, 0, "", "Lorem Ipsum", address(0), new bytes32[](1));
    }

    function testRevert_setProposalType_InvalidApprovalThreshold(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectRevert(IProposalTypesConfigurator.InvalidApprovalThreshold.selector);
        proposalTypesConfigurator.setProposalType(0, 0, 10_001, "", "Lorem Ipsum", address(0), new bytes32[](1));
    }

    function testRevert_setScopeForProposalType_NotAdmin(address _actor) public {
        vm.assume(_actor != admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);
        vm.expectRevert(IProposalTypesConfigurator.NotAdmin.selector);
        proposalTypesConfigurator.setScopeForProposalType(
            1, txTypeHash, txEncoded, new bytes[](1), new IProposalTypesConfigurator.Comparators[](1)
        );
    }

    function testRevert_setScopeForProposalType_InvalidProposalType() public {
        vm.prank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);
        vm.expectRevert(IProposalTypesConfigurator.InvalidProposalType.selector);
        proposalTypesConfigurator.setScopeForProposalType(
            2, txTypeHash, txEncoded, new bytes[](1), new IProposalTypesConfigurator.Comparators[](1)
        );
    }

    function testRevert_setScopeForProposalType_InvalidParameterConditions() public {
        vm.prank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);
        vm.expectRevert(IProposalTypesConfigurator.InvalidParameterConditions.selector);
        proposalTypesConfigurator.setScopeForProposalType(
            0, txTypeHash, txEncoded, new bytes[](2), new IProposalTypesConfigurator.Comparators[](1)
        );
    }

    function testRevert_setScopeForProposalType_NoDuplicateTxTypes() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);
        proposalTypesConfigurator.setScopeForProposalType(
            0, txTypeHash, txEncoded, new bytes[](1), new IProposalTypesConfigurator.Comparators[](1)
        );

        vm.expectRevert(IProposalTypesConfigurator.NoDuplicateTxTypes.selector);
        proposalTypesConfigurator.setScopeForProposalType(
            0, txTypeHash, txEncoded, new bytes[](1), new IProposalTypesConfigurator.Comparators[](1)
        );
        vm.stopPrank();
    }
}

contract UpdateScopeForProposalType is ProposalTypesConfiguratorTest {
    function testFuzz_UpdateScopeForProposalType(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        bytes32[] memory transactions = new bytes32[](1);
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", transactions);
        proposalTypesConfigurator.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0), transactions);

        vm.startPrank(admin);
        bytes32 txTypeHash1 = keccak256("transfer(address,address,uint)");
        bytes memory txEncoded1 = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);

        bytes32 txTypeHash2 = keccak256("initialize(address,address)");
        bytes memory txEncoded2 = abi.encode("initialize(address,address)", 0xdeadbeef, 0xdeadbeef);
        bytes[] memory parameters = new bytes[](1);
        IProposalTypesConfigurator.Comparators[] memory comparators = new IProposalTypesConfigurator.Comparators[](1);

        proposalTypesConfigurator.setScopeForProposalType(0, txTypeHash1, txEncoded1, parameters, comparators);

        IProposalTypesConfigurator.Scope memory scope = IProposalTypesConfigurator.Scope(
            txTypeHash2, txEncoded2, new bytes[](1), new IProposalTypesConfigurator.Comparators[](1)
        );
        proposalTypesConfigurator.updateScopeForProposalType(0, scope);
        vm.stopPrank();

        bytes memory limit1 = proposalTypesConfigurator.getLimit(0, txTypeHash1);
        bytes memory limit2 = proposalTypesConfigurator.getLimit(0, txTypeHash2);
        assertEq(limit1, txEncoded1);
        assertEq(limit2, txEncoded2);
    }

    function testRevert_updateScopeForProposalType_InvalidProposalType() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);

        vm.expectRevert(IProposalTypesConfigurator.InvalidProposalType.selector);
        IProposalTypesConfigurator.Scope memory scope = IProposalTypesConfigurator.Scope(
            txTypeHash, txEncoded, new bytes[](1), new IProposalTypesConfigurator.Comparators[](1)
        );
        proposalTypesConfigurator.updateScopeForProposalType(3, scope);
        vm.stopPrank();
    }

    function testRevert_updateScopeForProposalType_NoDuplicateTxTypes() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);

        proposalTypesConfigurator.setScopeForProposalType(
            0, txTypeHash, txEncoded, new bytes[](1), new IProposalTypesConfigurator.Comparators[](1)
        );

        vm.expectRevert(IProposalTypesConfigurator.NoDuplicateTxTypes.selector);
        IProposalTypesConfigurator.Scope memory scope = IProposalTypesConfigurator.Scope(
            txTypeHash, txEncoded, new bytes[](1), new IProposalTypesConfigurator.Comparators[](1)
        );
        proposalTypesConfigurator.updateScopeForProposalType(0, scope);
        vm.stopPrank();
    }

    function testRevert_updateScopeForProposalType_InvalidParametersCondition() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);

        IProposalTypesConfigurator.Scope memory scope = IProposalTypesConfigurator.Scope(
            txTypeHash, txEncoded, new bytes[](1), new IProposalTypesConfigurator.Comparators[](2)
        );
        vm.expectRevert(IProposalTypesConfigurator.InvalidParameterConditions.selector);
        proposalTypesConfigurator.updateScopeForProposalType(0, scope);
        vm.stopPrank();
    }
}

contract getLimit is ProposalTypesConfiguratorTest {
    function testRevert_getLimit_InvalidProposalType() public {
        vm.expectRevert(IProposalTypesConfigurator.InvalidProposalType.selector);
        proposalTypesConfigurator.getLimit(3, keccak256("foobar(address,address)"));
    }

    function testRevert_getLimit_InvalidScope() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);

        proposalTypesConfigurator.setScopeForProposalType(
            0, txTypeHash, txEncoded, new bytes[](1), new IProposalTypesConfigurator.Comparators[](1)
        );
        vm.stopPrank();

        vm.expectRevert(IProposalTypesConfigurator.InvalidScope.selector);
        proposalTypesConfigurator.getLimit(0, keccak256("foobar(address,address)"));
    }
}

contract ValidateProposedTx is ProposalTypesConfiguratorTest {
    function testFuzz_ValidateProposedTx() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address _from = makeAddr("from");
        address _to = makeAddr("to");

        bytes memory proposedTx = abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(15));
        bool valid = proposalTypesConfigurator.validateProposedTx(proposedTx, 0, txTypeHash);
        assertTrue(valid);
    }

    function testRevert_ValidateProposedTx_Invalid4ByteSelector() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address _from = makeAddr("from");
        address _to = makeAddr("to");

        bytes memory proposedTx = abi.encodeWithSignature("foobar(address,address,uint256)", _from, _to, uint256(15));
        vm.expectRevert(IProposalTypesConfigurator.Invalid4ByteSelector.selector);
        bool valid = proposalTypesConfigurator.validateProposedTx(proposedTx, 0, txTypeHash);
    }

    function testRevert_ValidateProposedTx_InvalidParamNotEqual() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address _from = makeAddr("from");
        address _to = makeAddr("to");

        bytes memory proposedTx = abi.encodeWithSignature("transfer(address,address,uint256)", _to, _from, uint256(15));
        vm.expectRevert(IProposalTypesConfigurator.InvalidParamNotEqual.selector);
        bool valid = proposalTypesConfigurator.validateProposedTx(proposedTx, 0, txTypeHash);
    }

    function testRevert_ValidateProposedTx_InvalidParamRange() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address _from = makeAddr("from");
        address _to = makeAddr("to");

        bytes memory proposedTx = abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(5));
        vm.expectRevert(IProposalTypesConfigurator.InvalidParamRange.selector);
        bool valid = proposalTypesConfigurator.validateProposedTx(proposedTx, 0, txTypeHash);
    }
}

contract GovernorMock {
    address immutable adminAddress;
    address immutable timelockAddress;

    constructor(address admin_, address _timelock) {
        adminAddress = admin_;
        timelockAddress = _timelock;
    }

    function admin() external view returns (address) {
        return adminAddress;
    }

    function timelock() external view returns (address) {
        return timelockAddress;
    }
}

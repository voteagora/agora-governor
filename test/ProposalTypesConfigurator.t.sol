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
        uint8 indexed proposalTypeId,
        uint16 quorum,
        uint16 approvalThreshold,
        string name,
        string description,
        address indexed module
    );

    event ScopeCreated(uint8 indexed proposalTypeId, bytes24 indexed scopeKey, bytes4 selector, string description);
    event ScopeDisabled(uint8 indexed proposalTypeId, bytes24 indexed scopeKey);
    event ScopeDeleted(uint8 indexed proposalTypeId, bytes24 indexed scopeKey);

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
        proposalTypesConfigurator =
            new ProposalTypesConfigurator(address(governor), new ProposalTypesConfigurator.ProposalType[](0));
        vm.stopPrank();

        vm.startPrank(admin);
        proposalTypesConfigurator.setProposalType(0, 3_000, 5_000, "Default", "Lorem Ipsum", address(0));
        proposalTypesConfigurator.setProposalType(1, 5_000, 7_000, "Alt", "Lorem Ipsum", address(0));

        // Setup Scope logic
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        address _from = makeAddr("from");
        address _to = makeAddr("to");
        bytes4 txEncoded = bytes4(abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(10)));

        bytes[] memory parameters = new bytes[](3);
        parameters[0] = abi.encode(uint256(uint160(_from)));
        parameters[1] = abi.encode(uint256(uint160(_to)));
        parameters[2] = abi.encode(uint256(10));

        IProposalTypesConfigurator.Comparators[] memory comparators = new IProposalTypesConfigurator.Comparators[](3);

        comparators[0] = IProposalTypesConfigurator.Comparators(0); // EQ
        comparators[1] = IProposalTypesConfigurator.Comparators(0); // EQ
        comparators[2] = IProposalTypesConfigurator.Comparators(2); // GREATER THAN

        IProposalTypesConfigurator.SupportedTypes[] memory types = new IProposalTypesConfigurator.SupportedTypes[](3);

        types[0] = IProposalTypesConfigurator.SupportedTypes(7); // address
        types[1] = IProposalTypesConfigurator.SupportedTypes(7); // address
        types[2] = IProposalTypesConfigurator.SupportedTypes(6); // uint256

        proposalTypesConfigurator.setScopeForProposalType(
            0, scopeKey, txEncoded, parameters, comparators, types, "lorem"
        );
        vm.stopPrank();
    }

    function _adminOrTimelock(uint256 _actorSeed) internal view returns (address) {
        if (_actorSeed % 2 == 1) return admin;
        else return governor.timelock();
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

    /**
     * @notice Unpacks the scope key into the constituent parts, i.e. contract address the first 20 bytes and the function selector as the last 4 bytes
     * @param self A byte24 key to be unpacked representing the key for a defined scope
     */
    function _unpack(bytes24 self) internal pure returns (address, bytes4) {
        bytes20 contractAddress;
        bytes4 selector;

        assembly ("memory-safe") {
            contractAddress := and(shl(mul(8, 0), self), shl(96, not(0)))
            selector := and(shl(mul(8, 20), self), shl(224, not(0)))
        }

        return (address(contractAddress), selector);
    }
}

contract Initialize is ProposalTypesConfiguratorTest {
    function test_SetsGovernor(address _actor, address _governor) public {
        vm.assume(_governor != address(0));
        ProposalTypesConfigurator proposalTypesConfigurator =
            new ProposalTypesConfigurator(address(_governor), new ProposalTypesConfigurator.ProposalType[](0));
        assertEq(_governor, address(proposalTypesConfigurator.GOVERNOR()));
    }

    function test_SetsProposalTypes(address _actor, uint8 _proposalTypes) public {
        ProposalTypesConfigurator.ProposalType[] memory proposalTypes =
            new ProposalTypesConfigurator.ProposalType[](_proposalTypes);
        ProposalTypesConfigurator proposalTypesConfigurator =
            new ProposalTypesConfigurator(address(governor), proposalTypes);
        for (uint8 i = 0; i < _proposalTypes; i++) {
            IProposalTypesConfigurator.ProposalType memory propType = proposalTypesConfigurator.proposalTypes(i);
            assertEq(propType.quorum, 0);
            assertEq(propType.approvalThreshold, 0);
            assertEq(propType.name, "");
        }
    }
}

contract ProposalTypes is ProposalTypesConfiguratorTest {
    function test_ScopeKeyPacking() public virtual {
        address contractAddress = makeAddr("contractAddress");
        bytes4 selector =
            bytes4(abi.encodeWithSignature("transfer(address,address,uint256)", address(0), address(0), uint256(100)));

        bytes24 key = _pack(contractAddress, selector);
        (address _contract, bytes4 _selector) = _unpack(key);
        assertEq(contractAddress, _contract);
        assertEq(selector, _selector);
    }

    function test_ProposalTypes() public view {
        IProposalTypesConfigurator.ProposalType memory propType = proposalTypesConfigurator.proposalTypes(0);

        assertEq(propType.quorum, 3_000);
        assertEq(propType.approvalThreshold, 5_000);
        assertEq(propType.name, "Default");
    }
}

contract GetSelector is ProposalTypesConfiguratorTest {
    function test_getSelector() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));

        bytes4 selector = proposalTypesConfigurator.getSelector(0, scopeKey);
        bytes4 expectedSelector = bytes4(txTypeHash);
        assertEq(selector, expectedSelector);
    }

    function test_Revert_getSelector_InvalidScope() public {
        bytes32 txTypeHash = keccak256("foobar(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));

        vm.expectRevert(IProposalTypesConfigurator.InvalidScope.selector);
        proposalTypesConfigurator.getSelector(0, scopeKey);
    }

    function test_Revert_getSelector_InvalidProposalType() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));

        vm.expectRevert(IProposalTypesConfigurator.InvalidProposalType.selector);
        proposalTypesConfigurator.getSelector(12, scopeKey);
    }
}

contract SetProposalType is ProposalTypesConfiguratorTest {
    function testFuzz_SetProposalType(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));
        proposalTypesConfigurator.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));

        IProposalTypesConfigurator.ProposalType memory propType = proposalTypesConfigurator.proposalTypes(0);

        assertEq(propType.quorum, 4_000);
        assertEq(propType.approvalThreshold, 6_000);
        assertEq(propType.name, "New Default");
        assertEq(propType.description, "Lorem Ipsum");

        vm.prank(_adminOrTimelock(_actorSeed));
        proposalTypesConfigurator.setProposalType(1, 0, 0, "Optimistic", "Lorem Ipsum", address(0));
        propType = proposalTypesConfigurator.proposalTypes(1);
        assertEq(propType.quorum, 0);
        assertEq(propType.approvalThreshold, 0);
        assertEq(propType.name, "Optimistic");
        assertEq(propType.description, "Lorem Ipsum");
    }

    function testFuzz_SetScopeForProposalType(uint256 _actorSeed) public {
        vm.startPrank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));
        proposalTypesConfigurator.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));
        vm.stopPrank();

        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes4 txEncoded = bytes4(abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10));
        bytes[] memory parameters = new bytes[](1);
        IProposalTypesConfigurator.Comparators[] memory comparators = new IProposalTypesConfigurator.Comparators[](1);

        vm.expectEmit();
        emit ScopeCreated(0, scopeKey, txEncoded, "Lorem Ipsum");
        IProposalTypesConfigurator.SupportedTypes[] memory types = new IProposalTypesConfigurator.SupportedTypes[](1);
        proposalTypesConfigurator.setScopeForProposalType(
            0, scopeKey, txEncoded, parameters, comparators, types, "Lorem Ipsum"
        );
        vm.stopPrank();

        bytes4 selector = proposalTypesConfigurator.getSelector(0, scopeKey);
        assertEq(selector, txEncoded);
    }

    function test_RevertIf_NotAdminOrTimelock(address _actor) public {
        vm.assume(_actor != admin && _actor != GovernorMock(governor).timelock());
        vm.expectRevert(IProposalTypesConfigurator.NotAdminOrTimelock.selector);
        proposalTypesConfigurator.setProposalType(0, 0, 0, "", "Lorem Ipsum", address(0));
    }

    function test_RevertIf_setProposalType_InvalidQuorum(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectRevert(IProposalTypesConfigurator.InvalidQuorum.selector);
        proposalTypesConfigurator.setProposalType(0, 10_001, 0, "", "Lorem Ipsum", address(0));
    }

    function testRevert_setProposalType_InvalidApprovalThreshold(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectRevert(IProposalTypesConfigurator.InvalidApprovalThreshold.selector);
        proposalTypesConfigurator.setProposalType(0, 0, 10_001, "", "Lorem Ipsum", address(0));
    }

    function testRevert_setScopeForProposalType_NotAdmin(address _actor) public {
        vm.assume(_actor != admin && _actor != GovernorMock(governor).timelock());
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes4 txEncoded = bytes4(abi.encode("transfer(address,address,uint256)", 0xdeadbeef, 0xdeadbeef, 10));
        vm.expectRevert(IProposalTypesConfigurator.NotAdminOrTimelock.selector);
        proposalTypesConfigurator.setScopeForProposalType(
            1,
            scopeKey,
            txEncoded,
            new bytes[](1),
            new IProposalTypesConfigurator.Comparators[](1),
            new IProposalTypesConfigurator.SupportedTypes[](1),
            "lorem"
        );
    }

    function testRevert_setScopeForProposalType_InvalidProposalType() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes4 txEncoded = bytes4(abi.encode("transfer(address,address,uint256)", 0xdeadbeef, 0xdeadbeef, 10));
        vm.expectRevert(IProposalTypesConfigurator.InvalidProposalType.selector);
        proposalTypesConfigurator.setScopeForProposalType(
            2,
            scopeKey,
            txEncoded,
            new bytes[](1),
            new IProposalTypesConfigurator.Comparators[](1),
            new IProposalTypesConfigurator.SupportedTypes[](1),
            "lorem"
        );
        vm.stopPrank();
    }

    function testRevert_setScopeForProposalType_InvalidParameterConditions() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes4 txEncoded = bytes4(abi.encode("transfer(address,address,uint256)", 0xdeadbeef, 0xdeadbeef, 10));
        vm.expectRevert(IProposalTypesConfigurator.InvalidParameterConditions.selector);
        proposalTypesConfigurator.setScopeForProposalType(
            0,
            scopeKey,
            txEncoded,
            new bytes[](2),
            new IProposalTypesConfigurator.Comparators[](1),
            new IProposalTypesConfigurator.SupportedTypes[](1),
            "Lorem"
        );
        vm.stopPrank();
    }

    function testRevert_setScopeForProposalType_MaxScopeLengthReached() public {
        vm.startPrank(admin);

        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes4 txEncoded = bytes4(abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10));
        bytes[] memory parameters = new bytes[](1);
        IProposalTypesConfigurator.Comparators[] memory comparators = new IProposalTypesConfigurator.Comparators[](1);
        IProposalTypesConfigurator.SupportedTypes[] memory types = new IProposalTypesConfigurator.SupportedTypes[](1);

        for (uint8 i = 0; i < proposalTypesConfigurator.MAX_SCOPE_LENGTH(); i++) {
            proposalTypesConfigurator.setScopeForProposalType(
                0, scopeKey, txEncoded, parameters, comparators, types, "Lorem Ipsum"
            );
        }

        vm.expectRevert(IProposalTypesConfigurator.MaxScopeLengthReached.selector);
        proposalTypesConfigurator.setScopeForProposalType(
            0, scopeKey, txEncoded, parameters, comparators, types, "Lorem Ipsum"
        );
        vm.stopPrank();
    }
}

contract AddScopeForProposalType is ProposalTypesConfiguratorTest {
    function testFuzz_AddScopeForProposalType(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));
        proposalTypesConfigurator.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));

        vm.startPrank(admin);
        bytes32 txTypeHash1 = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey1 = _pack(contractAddress, bytes4(txTypeHash1));
        bytes4 txEncoded1 = bytes4(abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10));

        bytes32 txTypeHash2 = keccak256("initialize(address,address)");
        bytes4 txEncoded2 = bytes4(abi.encode("initialize(address,address)", 0xdeadbeef, 0xdeadbeef));
        bytes[] memory parameters = new bytes[](1);
        bytes24 scopeKey2 = _pack(contractAddress, bytes4(txTypeHash2));
        IProposalTypesConfigurator.Comparators[] memory comparators = new IProposalTypesConfigurator.Comparators[](1);

        proposalTypesConfigurator.setScopeForProposalType(
            0,
            scopeKey1,
            txEncoded1,
            parameters,
            comparators,
            new IProposalTypesConfigurator.SupportedTypes[](1),
            "Lorem"
        );

        IProposalTypesConfigurator.Scope memory scope = IProposalTypesConfigurator.Scope(
            scopeKey2,
            txEncoded2,
            new bytes[](1),
            new IProposalTypesConfigurator.Comparators[](1),
            new IProposalTypesConfigurator.SupportedTypes[](1),
            0,
            "Lorem",
            true
        );

        emit ScopeCreated(0, scope.key, scope.selector, "Lorem");
        proposalTypesConfigurator.addScopeForProposalType(0, scope);
        vm.stopPrank();

        bytes4 limit1 = proposalTypesConfigurator.getSelector(0, scopeKey1);
        bytes4 limit2 = proposalTypesConfigurator.getSelector(0, scopeKey2);
        assertEq(limit1, txEncoded1);
        assertEq(limit2, txEncoded2);
    }

    function testRevert_addScopeForProposalType_InvalidProposalType() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes4 txEncoded = bytes4(abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10));

        vm.expectRevert(IProposalTypesConfigurator.InvalidProposalType.selector);
        IProposalTypesConfigurator.Scope memory scope = IProposalTypesConfigurator.Scope(
            scopeKey,
            txEncoded,
            new bytes[](1),
            new IProposalTypesConfigurator.Comparators[](1),
            new IProposalTypesConfigurator.SupportedTypes[](1),
            3,
            "Lorem",
            true
        );
        proposalTypesConfigurator.addScopeForProposalType(3, scope);
        vm.stopPrank();
    }

    function testRevert_addScopeForProposalType_InvalidParametersCondition() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes4 txEncoded = bytes4(abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10));

        IProposalTypesConfigurator.Scope memory scope = IProposalTypesConfigurator.Scope(
            scopeKey,
            txEncoded,
            new bytes[](1),
            new IProposalTypesConfigurator.Comparators[](2),
            new IProposalTypesConfigurator.SupportedTypes[](1),
            0,
            "Lorem",
            true
        );
        vm.expectRevert(IProposalTypesConfigurator.InvalidParameterConditions.selector);
        proposalTypesConfigurator.addScopeForProposalType(0, scope);
        vm.stopPrank();
    }

    function testRevert_addScopeForProposalType_MaxScopeLengthReached() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes4 txEncoded = bytes4(abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10));
        bytes[] memory parameters = new bytes[](1);
        IProposalTypesConfigurator.Comparators[] memory comparators = new IProposalTypesConfigurator.Comparators[](1);
        IProposalTypesConfigurator.SupportedTypes[] memory types = new IProposalTypesConfigurator.SupportedTypes[](1);

        IProposalTypesConfigurator.Scope memory scope =
            IProposalTypesConfigurator.Scope(scopeKey, txEncoded, parameters, comparators, types, 0, "Lorem", true);

        for (uint8 i = 0; i < proposalTypesConfigurator.MAX_SCOPE_LENGTH(); i++) {
            proposalTypesConfigurator.addScopeForProposalType(0, scope);
        }

        vm.expectRevert(IProposalTypesConfigurator.MaxScopeLengthReached.selector);
        proposalTypesConfigurator.addScopeForProposalType(0, scope);
        vm.stopPrank();
    }
}

contract ValidateProposedTx is ProposalTypesConfiguratorTest {
    function testFuzz_ValidateProposedTx() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        address _from = makeAddr("from");
        address _to = makeAddr("to");

        bytes memory proposedTx = abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(15));
        proposalTypesConfigurator.validateProposedTx(proposedTx, 0, scopeKey);
    }

    function testRevert_ValidateProposedTx_Invalid4ByteSelector() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        address _from = makeAddr("from");
        address _to = makeAddr("to");

        bytes memory proposedTx = abi.encodeWithSignature("foobar(address,address,uint256)", _from, _to, uint256(15));
        vm.expectRevert(IProposalTypesConfigurator.Invalid4ByteSelector.selector);
        proposalTypesConfigurator.validateProposedTx(proposedTx, 0, scopeKey);
    }

    function testRevert_ValidateProposedTx_InvalidParamNotEqual() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        address _from = makeAddr("from");
        address _to = makeAddr("to");

        bytes memory proposedTx = abi.encodeWithSignature("transfer(address,address,uint256)", _to, _from, uint256(15));
        vm.expectRevert(IProposalTypesConfigurator.InvalidParamNotEqual.selector);
        proposalTypesConfigurator.validateProposedTx(proposedTx, 0, scopeKey);
    }

    function testRevert_ValidateProposedTx_InvalidParamRange() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        address _from = makeAddr("from");
        address _to = makeAddr("to");

        bytes memory proposedTx = abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(5));
        vm.expectRevert(IProposalTypesConfigurator.InvalidParamRange.selector);
        proposalTypesConfigurator.validateProposedTx(proposedTx, 0, scopeKey);
    }
}

contract ValidateProposalData is ProposalTypesConfiguratorTest {
    function testRevert_ValidateProposalData_InvalidCalldatas() public {
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.expectRevert(IProposalTypesConfigurator.InvalidCalldata.selector);
        proposalTypesConfigurator.validateProposalData(targets, calldatas, 0);
    }

    function testRevert_ValidateProposalData_InvalidCalldatasLength() public {
        address[] memory targets = new address[](0);
        bytes[] memory calldatas = new bytes[](0);

        vm.expectRevert(IProposalTypesConfigurator.InvalidCalldatasLength.selector);
        proposalTypesConfigurator.validateProposalData(targets, calldatas, 0);
    }
}

contract DisableScope is ProposalTypesConfiguratorTest {
    function testFuzz_DisableScope(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));

        vm.expectEmit();
        emit ScopeDisabled(0, scopeKey);
        proposalTypesConfigurator.disableScope(0, scopeKey, 0);
    }
}

contract DeleteScope is ProposalTypesConfiguratorTest {
    function testFuzz_DeleteScope(uint256 _actorSeed) public {
        vm.startPrank(_adminOrTimelock(_actorSeed));
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));

        assertEq(proposalTypesConfigurator.assignedScopes(0, scopeKey).length, 1);
        vm.expectEmit();
        emit ScopeDeleted(0, scopeKey);
        proposalTypesConfigurator.deleteScope(0, scopeKey, 0);
        assertEq(proposalTypesConfigurator.assignedScopes(0, scopeKey).length, 0);

        vm.stopPrank();
    }
}

contract MultipleScopeValidation is ProposalTypesConfiguratorTest {
    function testFuzz_MultipleScopeValidationRange(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));
        proposalTypesConfigurator.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));

        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        address _from = makeAddr("from");
        address _to = makeAddr("to");
        bytes4 txEncoded1 =
            bytes4(abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(10)));

        bytes[] memory parameters1 = new bytes[](3);
        parameters1[0] = abi.encode(uint256(uint160(_from)));
        parameters1[1] = abi.encode(uint256(uint160(_to)));
        parameters1[2] = abi.encode(uint256(10));

        IProposalTypesConfigurator.Comparators[] memory comparators1 = new IProposalTypesConfigurator.Comparators[](3);

        comparators1[0] = IProposalTypesConfigurator.Comparators(0); // EQ
        comparators1[1] = IProposalTypesConfigurator.Comparators(0); // EQ
        comparators1[2] = IProposalTypesConfigurator.Comparators(2); // GREATER THAN

        IProposalTypesConfigurator.SupportedTypes[] memory types = new IProposalTypesConfigurator.SupportedTypes[](3);

        types[0] = IProposalTypesConfigurator.SupportedTypes(7); // address
        types[1] = IProposalTypesConfigurator.SupportedTypes(7); // address
        types[2] = IProposalTypesConfigurator.SupportedTypes(6); // uint256

        proposalTypesConfigurator.setScopeForProposalType(
            0, scopeKey, txEncoded1, parameters1, comparators1, types, "Lorem"
        );

        bytes[] memory parameters2 = new bytes[](3);
        parameters2[0] = abi.encode(uint256(uint160(_from)));
        parameters2[1] = abi.encode(uint256(uint160(_to)));
        parameters2[2] = abi.encode(uint256(50));

        IProposalTypesConfigurator.Comparators[] memory comparators2 = new IProposalTypesConfigurator.Comparators[](3);

        comparators2[0] = IProposalTypesConfigurator.Comparators(0); // EQ
        comparators2[1] = IProposalTypesConfigurator.Comparators(0); // EQ
        comparators2[2] = IProposalTypesConfigurator.Comparators(1); // LESS THAN

        bytes4 txEncoded2 =
            bytes4(abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(50)));
        proposalTypesConfigurator.setScopeForProposalType(
            0, scopeKey, txEncoded2, parameters2, comparators2, types, "Lorem"
        );

        vm.stopPrank();
        bytes memory proposedTx = abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(15));
        proposalTypesConfigurator.validateProposedTx(proposedTx, 0, scopeKey);
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

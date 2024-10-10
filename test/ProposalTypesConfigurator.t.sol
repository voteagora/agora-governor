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
        bytes24[] validScopes
    );

    event ScopeCreated(uint8 indexed proposalTypeId, bytes24 indexed scopeKey, bytes encodedLimit);
    event ScopeDisabled(bytes24 indexed scopeKey);

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
        bytes24[] memory scopes = new bytes24[](1);
        proposalTypesConfigurator.setProposalType(0, 3_000, 5_000, "Default", "Lorem Ipsum", address(0), scopes);
        proposalTypesConfigurator.setProposalType(1, 5_000, 7_000, "Alt", "Lorem Ipsum", address(0), scopes);

        // Setup Scope logic
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
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

        proposalTypesConfigurator.setScopeForProposalType(0, scopeKey, txEncoded, parameters, comparators);
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

contract SetProposalType is ProposalTypesConfiguratorTest {
    function testFuzz_SetProposalType(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        bytes24[] memory scopes = new bytes24[](1);
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", scopes);
        proposalTypesConfigurator.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0), scopes);

        IProposalTypesConfigurator.ProposalType memory propType = proposalTypesConfigurator.proposalTypes(0);

        assertEq(propType.quorum, 4_000);
        assertEq(propType.approvalThreshold, 6_000);
        assertEq(propType.name, "New Default");
        assertEq(propType.description, "Lorem Ipsum");

        vm.prank(_adminOrTimelock(_actorSeed));
        proposalTypesConfigurator.setProposalType(1, 0, 0, "Optimistic", "Lorem Ipsum", address(0), scopes);
        propType = proposalTypesConfigurator.proposalTypes(1);
        assertEq(propType.quorum, 0);
        assertEq(propType.approvalThreshold, 0);
        assertEq(propType.name, "Optimistic");
        assertEq(propType.description, "Lorem Ipsum");
    }

    function testFuzz_SetScopeForProposalType(uint256 _actorSeed) public {
        vm.startPrank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        bytes24[] memory scopes = new bytes24[](1);
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", scopes);
        proposalTypesConfigurator.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0), scopes);
        vm.stopPrank();

        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);
        bytes[] memory parameters = new bytes[](1);
        IProposalTypesConfigurator.Comparators[] memory comparators = new IProposalTypesConfigurator.Comparators[](1);

        vm.expectEmit();
        emit ScopeCreated(0, scopeKey, txEncoded);
        proposalTypesConfigurator.setScopeForProposalType(0, scopeKey, txEncoded, parameters, comparators);

        vm.stopPrank();
    }

    function test_RevertIf_NotAdminOrTimelock(address _actor) public {
        vm.assume(_actor != admin && _actor != GovernorMock(governor).timelock());
        vm.expectRevert(IProposalTypesConfigurator.NotAdminOrTimelock.selector);
        proposalTypesConfigurator.setProposalType(0, 0, 0, "", "Lorem Ipsum", address(0), new bytes24[](1));
    }

    function test_RevertIf_setProposalType_InvalidQuorum(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectRevert(IProposalTypesConfigurator.InvalidQuorum.selector);
        proposalTypesConfigurator.setProposalType(0, 10_001, 0, "", "Lorem Ipsum", address(0), new bytes24[](1));
    }

    function testRevert_setProposalType_InvalidApprovalThreshold(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectRevert(IProposalTypesConfigurator.InvalidApprovalThreshold.selector);
        proposalTypesConfigurator.setProposalType(0, 0, 10_001, "", "Lorem Ipsum", address(0), new bytes24[](1));
    }

    function testRevert_setScopeForProposalType_NotAdmin(address _actor) public {
        vm.assume(_actor != admin && _actor != GovernorMock(governor).timelock());
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);
        vm.expectRevert(IProposalTypesConfigurator.NotAdminOrTimelock.selector);
        proposalTypesConfigurator.setScopeForProposalType(
            1, scopeKey, txEncoded, new bytes[](1), new IProposalTypesConfigurator.Comparators[](1)
        );
    }

    function testRevert_setScopeForProposalType_InvalidProposalType() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);
        vm.expectRevert(IProposalTypesConfigurator.InvalidProposalType.selector);
        proposalTypesConfigurator.setScopeForProposalType(
            2, scopeKey, txEncoded, new bytes[](1), new IProposalTypesConfigurator.Comparators[](1)
        );
        vm.stopPrank();
    }

    function testRevert_setScopeForProposalType_InvalidParameterConditions() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes memory txEncoded = abi.encode("transfer(address,address,uint256)", 0xdeadbeef, 0xdeadbeef, 10);
        vm.expectRevert(IProposalTypesConfigurator.InvalidParameterConditions.selector);
        proposalTypesConfigurator.setScopeForProposalType(
            0, scopeKey, txEncoded, new bytes[](2), new IProposalTypesConfigurator.Comparators[](1)
        );
        vm.stopPrank();
    }
}

contract AddScopeForProposalType is ProposalTypesConfiguratorTest {
    function testFuzz_AddScopeForProposalType(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        bytes24[] memory scopes = new bytes24[](1);
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", scopes);
        proposalTypesConfigurator.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0), scopes);

        vm.startPrank(admin);
        bytes32 txTypeHash1 = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey1 = _pack(contractAddress, bytes4(txTypeHash1));
        bytes memory txEncoded1 = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);

        bytes32 txTypeHash2 = keccak256("initialize(address,address)");
        bytes memory txEncoded2 = abi.encode("initialize(address,address)", 0xdeadbeef, 0xdeadbeef);
        bytes[] memory parameters = new bytes[](1);
        bytes24 scopeKey2 = _pack(contractAddress, bytes4(txTypeHash2));
        IProposalTypesConfigurator.Comparators[] memory comparators = new IProposalTypesConfigurator.Comparators[](1);

        proposalTypesConfigurator.setScopeForProposalType(0, scopeKey1, txEncoded1, parameters, comparators);

        IProposalTypesConfigurator.Scope memory scope = IProposalTypesConfigurator.Scope(
            scopeKey2, txEncoded2, new bytes[](1), new IProposalTypesConfigurator.Comparators[](1), 0
        );

        emit ScopeCreated(0, scope.key, scope.encodedLimits);
        proposalTypesConfigurator.addScopeForProposalType(0, scope);
        vm.stopPrank();
    }

    function testRevert_addScopeForProposalType_InvalidProposalType() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);

        vm.expectRevert(IProposalTypesConfigurator.InvalidProposalType.selector);
        IProposalTypesConfigurator.Scope memory scope = IProposalTypesConfigurator.Scope(
            scopeKey, txEncoded, new bytes[](1), new IProposalTypesConfigurator.Comparators[](1), 3
        );
        proposalTypesConfigurator.addScopeForProposalType(3, scope);
        vm.stopPrank();
    }

    function testRevert_addScopeForProposalType_InvalidParametersCondition() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes memory txEncoded = abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10);

        IProposalTypesConfigurator.Scope memory scope = IProposalTypesConfigurator.Scope(
            scopeKey, txEncoded, new bytes[](1), new IProposalTypesConfigurator.Comparators[](2), 0
        );
        vm.expectRevert(IProposalTypesConfigurator.InvalidParameterConditions.selector);
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

contract DisableScope is ProposalTypesConfiguratorTest {
    function testFuzz_DisableScope(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));

        vm.expectEmit();
        emit ScopeDisabled(scopeKey);
        proposalTypesConfigurator.disableScope(scopeKey);
    }
}

contract MultipleScopeValidation is ProposalTypesConfiguratorTest {
    function testFuzz_MultipleScopeValidationRange(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        bytes24[] memory scopes = new bytes24[](1);
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", scopes);
        proposalTypesConfigurator.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0), scopes);

        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        address _from = makeAddr("from");
        address _to = makeAddr("to");
        bytes memory txEncoded1 = abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(10));

        bytes[] memory parameters1 = new bytes[](3);
        parameters1[0] = abi.encode(uint256(uint160(_from)));
        parameters1[1] = abi.encode(uint256(uint160(_to)));
        parameters1[2] = abi.encode(uint256(10));

        IProposalTypesConfigurator.Comparators[] memory comparators1 = new IProposalTypesConfigurator.Comparators[](3);

        comparators1[0] = IProposalTypesConfigurator.Comparators(1); // EQ
        comparators1[1] = IProposalTypesConfigurator.Comparators(1); // EQ
        comparators1[2] = IProposalTypesConfigurator.Comparators(3); // GREATER THAN

        proposalTypesConfigurator.setScopeForProposalType(0, scopeKey, txEncoded1, parameters1, comparators1);

        bytes[] memory parameters2 = new bytes[](3);
        parameters2[0] = abi.encode(uint256(uint160(_from)));
        parameters2[1] = abi.encode(uint256(uint160(_to)));
        parameters2[2] = abi.encode(uint256(50));

        IProposalTypesConfigurator.Comparators[] memory comparators2 = new IProposalTypesConfigurator.Comparators[](3);

        comparators2[0] = IProposalTypesConfigurator.Comparators(1); // EQ
        comparators2[1] = IProposalTypesConfigurator.Comparators(1); // EQ
        comparators2[2] = IProposalTypesConfigurator.Comparators(2); // LESS THAN

        bytes memory txEncoded2 = abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(50));
        proposalTypesConfigurator.setScopeForProposalType(0, scopeKey, txEncoded2, parameters2, comparators2);

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

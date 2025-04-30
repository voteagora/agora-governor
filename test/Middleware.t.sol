// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";

import {Hooks} from "src/libraries/Hooks.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";
import {ApprovalVotingModuleMock} from "test/mocks/ApprovalVotingModuleMock.sol";

import {IMiddleware} from "src/interfaces/IMiddleware.sol";
import {Middleware} from "src/Middleware.sol";

import {MockToken} from "test/mocks/MockToken.sol";
import {Deployers} from "test/utils/Deployers.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MiddlewareTest is Test, Deployers {
    ApprovalVotingModuleMock module;
    Middleware middleware;

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
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        module = ApprovalVotingModuleMock(
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
            "test/mocks/ApprovalVotingModuleMock.sol:ApprovalVotingModuleMock",
            abi.encode(address(governor)),
            address(module)
        );

        vm.startPrank(admin);
        middleware.setProposalType(0, 3_000, 5_000, "Default", "Lorem Ipsum", address(0));
        middleware.setProposalType(1, 5_000, 7_000, "Alt", "Lorem Ipsum", address(0));

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

        IMiddleware.Comparators[] memory comparators = new IMiddleware.Comparators[](3);

        comparators[0] = IMiddleware.Comparators(0); // EQ
        comparators[1] = IMiddleware.Comparators(0); // EQ
        comparators[2] = IMiddleware.Comparators(2); // GREATER THAN

        IMiddleware.SupportedTypes[] memory types = new IMiddleware.SupportedTypes[](3);

        types[0] = IMiddleware.SupportedTypes(7); // address
        types[1] = IMiddleware.SupportedTypes(7); // address
        types[2] = IMiddleware.SupportedTypes(6); // uint256

        middleware.setScopeForProposalType(0, scopeKey, txEncoded, parameters, comparators, types, "lorem");
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

contract Initialize is MiddlewareTest {
    function test_SetsGovernor() public view {
        assertEq(address(governor), address(middleware.governor()));
    }
}

contract ProposalTypes is MiddlewareTest {
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
        IMiddleware.ProposalType memory propType = middleware.proposalTypes(0);

        assertEq(propType.quorum, 3_000);
        assertEq(propType.approvalThreshold, 5_000);
        assertEq(propType.name, "Default");
    }
}

contract GetSelector is MiddlewareTest {
    function test_getSelector() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));

        bytes4 selector = middleware.getSelector(0, scopeKey);
        bytes4 expectedSelector = bytes4(txTypeHash);
        assertEq(selector, expectedSelector);
    }

    function test_Revert_getSelector_InvalidScope() public {
        bytes32 txTypeHash = keccak256("foobar(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));

        vm.expectRevert(IMiddleware.InvalidScope.selector);
        middleware.getSelector(0, scopeKey);
    }

    function test_Revert_getSelector_InvalidProposalType() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));

        vm.expectRevert(IMiddleware.InvalidProposalType.selector);
        middleware.getSelector(12, scopeKey);
    }
}

contract SetProposalType is MiddlewareTest {
    function testFuzz_SetProposalType(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));
        middleware.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));

        IMiddleware.ProposalType memory propType = middleware.proposalTypes(0);

        assertEq(propType.quorum, 4_000);
        assertEq(propType.approvalThreshold, 6_000);
        assertEq(propType.name, "New Default");
        assertEq(propType.description, "Lorem Ipsum");

        vm.prank(_adminOrTimelock(_actorSeed));
        middleware.setProposalType(1, 0, 0, "Optimistic", "Lorem Ipsum", address(0));
        propType = middleware.proposalTypes(1);
        assertEq(propType.quorum, 0);
        assertEq(propType.approvalThreshold, 0);
        assertEq(propType.name, "Optimistic");
        assertEq(propType.description, "Lorem Ipsum");
    }

    function testFuzz_SetScopeForProposalType(uint256 _actorSeed) public {
        vm.startPrank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));
        middleware.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));
        vm.stopPrank();

        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes4 txEncoded = bytes4(abi.encode("transfer(address,address,uint)", 0xdeadbeef, 0xdeadbeef, 10));
        bytes[] memory parameters = new bytes[](1);
        IMiddleware.Comparators[] memory comparators = new IMiddleware.Comparators[](1);

        vm.expectEmit();
        emit ScopeCreated(0, scopeKey, txEncoded, "Lorem Ipsum");
        IMiddleware.SupportedTypes[] memory types = new IMiddleware.SupportedTypes[](1);
        middleware.setScopeForProposalType(0, scopeKey, txEncoded, parameters, comparators, types, "Lorem Ipsum");
        vm.stopPrank();

        bytes4 selector = middleware.getSelector(0, scopeKey);
        assertEq(selector, txEncoded);
    }

    function test_RevertIf_NotAdminOrTimelock(address _actor) public {
        vm.assume(_actor != admin && _actor != governor.timelock());
        vm.expectRevert(IMiddleware.NotAdminOrTimelock.selector);
        middleware.setProposalType(0, 0, 0, "", "Lorem Ipsum", address(0));
    }

    function test_RevertIf_setProposalType_InvalidQuorum(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectRevert(IMiddleware.InvalidQuorum.selector);
        middleware.setProposalType(0, 10_001, 0, "", "Lorem Ipsum", address(0));
    }

    function testRevert_setProposalType_InvalidApprovalThreshold(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectRevert(IMiddleware.InvalidApprovalThreshold.selector);
        middleware.setProposalType(0, 0, 10_001, "", "Lorem Ipsum", address(0));
    }

    function testRevert_setScopeForProposalType_NotAdmin(address _actor) public {
        vm.assume(_actor != admin && _actor != governor.timelock());
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes4 txEncoded = bytes4(abi.encode("transfer(address,address,uint256)", 0xdeadbeef, 0xdeadbeef, 10));
        vm.expectRevert(IMiddleware.NotAdminOrTimelock.selector);
        middleware.setScopeForProposalType(
            1,
            scopeKey,
            txEncoded,
            new bytes[](1),
            new IMiddleware.Comparators[](1),
            new IMiddleware.SupportedTypes[](1),
            "lorem"
        );
    }

    function testRevert_setScopeForProposalType_InvalidProposalType() public {
        vm.startPrank(admin);
        bytes32 txTypeHash = keccak256("transfer(address,address,uint)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        bytes4 txEncoded = bytes4(abi.encode("transfer(address,address,uint256)", 0xdeadbeef, 0xdeadbeef, 10));
        vm.expectRevert(IMiddleware.InvalidProposalType.selector);
        middleware.setScopeForProposalType(
            2,
            scopeKey,
            txEncoded,
            new bytes[](1),
            new IMiddleware.Comparators[](1),
            new IMiddleware.SupportedTypes[](1),
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
        vm.expectRevert(IMiddleware.InvalidParameterConditions.selector);
        middleware.setScopeForProposalType(
            0,
            scopeKey,
            txEncoded,
            new bytes[](2),
            new IMiddleware.Comparators[](1),
            new IMiddleware.SupportedTypes[](1),
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
        IMiddleware.Comparators[] memory comparators = new IMiddleware.Comparators[](1);
        IMiddleware.SupportedTypes[] memory types = new IMiddleware.SupportedTypes[](1);

        for (uint8 i = 0; i < middleware.MAX_SCOPE_LENGTH(); i++) {
            middleware.setScopeForProposalType(0, scopeKey, txEncoded, parameters, comparators, types, "Lorem Ipsum");
        }

        vm.expectRevert(IMiddleware.MaxScopeLengthReached.selector);
        middleware.setScopeForProposalType(0, scopeKey, txEncoded, parameters, comparators, types, "Lorem Ipsum");
        vm.stopPrank();
    }
}

contract ValidateProposedTx is MiddlewareTest {
    function testFuzz_ValidateProposedTx() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        address _from = makeAddr("from");
        address _to = makeAddr("to");

        bytes memory proposedTx = abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(15));
        middleware.validateProposedTx(proposedTx, 0, scopeKey);
    }

    function testRevert_ValidateProposedTx_Invalid4ByteSelector() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        address _from = makeAddr("from");
        address _to = makeAddr("to");

        bytes memory proposedTx = abi.encodeWithSignature("foobar(address,address,uint256)", _from, _to, uint256(15));
        vm.expectRevert(IMiddleware.Invalid4ByteSelector.selector);
        middleware.validateProposedTx(proposedTx, 0, scopeKey);
    }

    function testRevert_ValidateProposedTx_InvalidParamNotEqual() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        address _from = makeAddr("from");
        address _to = makeAddr("to");

        bytes memory proposedTx = abi.encodeWithSignature("transfer(address,address,uint256)", _to, _from, uint256(15));
        vm.expectRevert(IMiddleware.InvalidParamNotEqual.selector);
        middleware.validateProposedTx(proposedTx, 0, scopeKey);
    }

    function testRevert_ValidateProposedTx_InvalidParamRange() public {
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));
        address _from = makeAddr("from");
        address _to = makeAddr("to");

        bytes memory proposedTx = abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(5));
        vm.expectRevert(IMiddleware.InvalidParamRange.selector);
        middleware.validateProposedTx(proposedTx, 0, scopeKey);
    }
}

contract ValidateProposalData is MiddlewareTest {
    function testRevert_ValidateProposalData_InvalidCalldatas() public {
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.expectRevert(IMiddleware.InvalidCalldata.selector);
        middleware.validateProposalData(targets, calldatas, 0);
    }

    function testRevert_ValidateProposalData_InvalidCalldatasLength() public {
        address[] memory targets = new address[](0);
        bytes[] memory calldatas = new bytes[](0);

        vm.expectRevert(IMiddleware.InvalidCalldatasLength.selector);
        middleware.validateProposalData(targets, calldatas, 0);
    }
}

contract DisableScope is MiddlewareTest {
    function testFuzz_DisableScope(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));

        vm.expectEmit();
        emit ScopeDisabled(0, scopeKey);
        middleware.disableScope(0, scopeKey, 0);
    }
}

contract DeleteScope is MiddlewareTest {
    function testFuzz_DeleteScope(uint256 _actorSeed) public {
        vm.startPrank(_adminOrTimelock(_actorSeed));
        bytes32 txTypeHash = keccak256("transfer(address,address,uint256)");
        address contractAddress = makeAddr("contract");
        bytes24 scopeKey = _pack(contractAddress, bytes4(txTypeHash));

        assertEq(middleware.assignedScopes(0, scopeKey).length, 1);
        vm.expectEmit();
        emit ScopeDeleted(0, scopeKey);
        middleware.deleteScope(0, scopeKey, 0);
        assertEq(middleware.assignedScopes(0, scopeKey).length, 0);

        vm.stopPrank();
    }
}

contract MultipleScopeValidation is MiddlewareTest {
    function testFuzz_MultipleScopeValidationRange(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));
        middleware.setProposalType(0, 4_000, 6_000, "New Default", "Lorem Ipsum", address(0));

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

        IMiddleware.Comparators[] memory comparators1 = new IMiddleware.Comparators[](3);

        comparators1[0] = IMiddleware.Comparators(0); // EQ
        comparators1[1] = IMiddleware.Comparators(0); // EQ
        comparators1[2] = IMiddleware.Comparators(2); // GREATER THAN

        IMiddleware.SupportedTypes[] memory types = new IMiddleware.SupportedTypes[](3);

        types[0] = IMiddleware.SupportedTypes(7); // address
        types[1] = IMiddleware.SupportedTypes(7); // address
        types[2] = IMiddleware.SupportedTypes(6); // uint256

        middleware.setScopeForProposalType(0, scopeKey, txEncoded1, parameters1, comparators1, types, "Lorem");

        bytes[] memory parameters2 = new bytes[](3);
        parameters2[0] = abi.encode(uint256(uint160(_from)));
        parameters2[1] = abi.encode(uint256(uint160(_to)));
        parameters2[2] = abi.encode(uint256(50));

        IMiddleware.Comparators[] memory comparators2 = new IMiddleware.Comparators[](3);

        comparators2[0] = IMiddleware.Comparators(0); // EQ
        comparators2[1] = IMiddleware.Comparators(0); // EQ
        comparators2[2] = IMiddleware.Comparators(1); // LESS THAN

        bytes4 txEncoded2 =
            bytes4(abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(50)));
        middleware.setScopeForProposalType(0, scopeKey, txEncoded2, parameters2, comparators2, types, "Lorem");

        vm.stopPrank();
        bytes memory proposedTx = abi.encodeWithSignature("transfer(address,address,uint256)", _from, _to, uint256(15));
        middleware.validateProposedTx(proposedTx, 0, scopeKey);
    }
}

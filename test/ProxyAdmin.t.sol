// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts-v4/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "src/ProxyAdmin.sol";
import {AgoraGovernorTest} from "test/AgoraGovernor.t.sol";
import {AgoraGovernor} from "test/mocks/AgoraGovernorMock.sol";

contract ProxyAdminTest is AgoraGovernorTest {
    event OwnerUpdated(address indexed owner, bool isOwner);

    TransparentUpgradeableProxy proxyContract;

    function setUp() public override {
        super.setUp();
        proxyContract = TransparentUpgradeableProxy(payable(governorProxy));
    }
}

contract Constructor is ProxyAdminTest {
    function testFuzz_AddsOwnersSuccessfully(address[] calldata _owners) public {
        ProxyAdmin proxyAdminContract = new ProxyAdmin(_owners);
        for (uint256 i; i < _owners.length; i++) {
            assertEq(proxyAdminContract.owners(_owners[i]), true);
        }
    }

    function testFuzz_EmitsOwnerUpdatedEventSuccessfully(address[] calldata _owners) public {
        for (uint256 i; i < _owners.length; i++) {
            vm.expectEmit();
            emit OwnerUpdated(_owners[i], true);
        }
        ProxyAdmin proxyAdminContract = new ProxyAdmin(_owners);
    }
}

contract UpdateOwner is ProxyAdminTest {
    function testFuzz_UpdatesOwnerSuccessfully(address _newOwner, bool _isOwner, uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        proxyAdminContract.updateOwner(_newOwner, _isOwner);
        assertEq(proxyAdminContract.owners(_newOwner), _isOwner);
    }

    function testFuzz_EmitsOwnerUpdatedEventSuccessfully(address _newOwner, bool _isOwner, uint256 _actorSeed) public {
        vm.expectEmit();
        emit OwnerUpdated(_newOwner, _isOwner);
        vm.prank(_adminOrTimelock(_actorSeed));
        proxyAdminContract.updateOwner(_newOwner, _isOwner);
    }

    function testFuzz_RevertIf_NotAdminOrTimelock(address _actor, address _newOwner) public {
        vm.assume(_actor != admin && _actor != address(timelock));
        vm.prank(_actor);
        vm.expectRevert("ProxyAdmin: caller is not one of the owners");
        proxyAdminContract.updateOwner(_newOwner, true);
    }
}

contract getProxyImplementation is ProxyAdminTest {
    function test_ReturnsProxyImplementationSuccessfully() public {
        assertEq(proxyAdminContract.getProxyImplementation(proxyContract), implementation);
    }
}

contract getProxyAdmin is ProxyAdminTest {
    function test_ReturnsProxyAdminSuccessfully() public {
        assertEq(proxyAdminContract.getProxyAdmin(proxyContract), address(proxyAdmin));
    }
}

contract ChangeProxyAdmin is ProxyAdminTest {
    function testFuzz_ChangesProxyAdminSuccessfully(address _newAdmin, uint256 _actorSeed) public {
        vm.assume(_newAdmin != address(0));
        vm.prank(_adminOrTimelock(_actorSeed));
        proxyAdminContract.changeProxyAdmin(proxyContract, _newAdmin);
        vm.prank(address(_newAdmin));
        assertEq(proxyContract.admin(), _newAdmin);
    }

    function testFuzz_RevertIf_NotAdminOrTimelock(address _actor, address _newAdmin) public {
        vm.assume(_actor != admin && _actor != address(timelock));
        vm.prank(_actor);
        vm.expectRevert("ProxyAdmin: caller is not one of the owners");
        proxyAdminContract.changeProxyAdmin(proxyContract, _newAdmin);
    }
}

contract Upgrade is ProxyAdminTest {
    function testFuzz_UpgradeSuccessfully(uint256 _actorSeed) public {
        address _newImplementation = address(new AgoraGovernor());
        vm.prank(_adminOrTimelock(_actorSeed));
        proxyAdminContract.upgrade(proxyContract, _newImplementation);
        vm.prank(proxyAdmin);
        assertEq(proxyContract.implementation(), _newImplementation);
    }

    function testFuzz_RevertIf_NotAdminOrTimelock(address _actor) public {
        vm.assume(_actor != admin && _actor != address(timelock));
        address _newImplementation = address(new AgoraGovernor());
        vm.prank(_actor);
        vm.expectRevert("ProxyAdmin: caller is not one of the owners");
        proxyAdminContract.upgrade(proxyContract, _newImplementation);
    }
}

contract UpgradeAndCall is ProxyAdminTest {
    function testFuzz_UpgradeAndCallSuccessfully(uint256 _actorSeed, uint256 _randomCounter) public {
        address _newImplementation = address(new UpgradeMock());
        bytes memory _data = abi.encodeCall(UpgradeMock.setCounter, (_randomCounter));
        vm.prank(_adminOrTimelock(_actorSeed));
        proxyAdminContract.upgradeAndCall(proxyContract, _newImplementation, _data);
        vm.prank(proxyAdmin);
        assertEq(proxyContract.implementation(), _newImplementation);
        assertEq(UpgradeMock(address(proxyContract)).counter(), _randomCounter);
    }

    function testFuzz_RevertIf_NotAdminOrTimeLock(address _actor, uint256 _randomCounter) public {
        vm.assume(_actor != admin && _actor != address(timelock));
        address _newImplementation = address(new UpgradeMock());
        bytes memory _data = abi.encodeCall(UpgradeMock.setCounter, (_randomCounter));
        vm.prank(_actor);
        vm.expectRevert("ProxyAdmin: caller is not one of the owners");
        proxyAdminContract.upgradeAndCall(proxyContract, _newImplementation, _data);
    }
}

contract UpgradeMock {
    uint256 public counter;

    function setCounter(uint256 _newCounter) public {
        counter = _newCounter;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {TokenDistributor} from "src/TokenDistributor.sol";
import {L2GovToken} from "ERC20VotesPartialDelegationUpgradeable/L2GovToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts-v4/proxy/ERC1967/ERC1967Proxy.sol";
import {Merkle} from "@murky/Merkle.sol";

contract TokenDistributorTest is Test {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address owner = makeAddr("owner");

    L2GovToken internal token;
    TokenDistributor internal distributor;
    Merkle internal merkle;

    bytes32[] internal data = new bytes32[](2);

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        token = L2GovToken(
            address(
                new ERC1967Proxy(
                    address(new L2GovToken()), abi.encodeCall(token.initialize, (owner, "L2 Gov Token", "gL2"))
                )
            )
        );

        vm.startPrank(owner);
        token.grantRole(token.MINTER_ROLE(), owner);
        vm.stopPrank();

        // Set up merkle root.
        merkle = new Merkle();

        data[0] = keccak256(bytes.concat(keccak256(abi.encode(address(this), 1000 ether))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(address(0x123), 1000 ether))));

        bytes32 root = merkle.getRoot(data);

        distributor = new TokenDistributor(root, address(token), owner);

        vm.prank(owner);
        token.mint(address(distributor), 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testClaim() public {
        bytes32[] memory proof = merkle.getProof(data, 0);

        assertEq(token.balanceOf(address(distributor)), 1000 ether);
        assertEq(token.balanceOf(address(this)), 0);
        assertFalse(distributor.hasClaimed(address(this)));

        vm.expectEmit(address(distributor));
        emit TokenDistributor.Claimed(address(this), 1000 ether);

        distributor.claim(1000 ether, proof);

        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(token.balanceOf(address(this)), 1000 ether);
        assertTrue(distributor.hasClaimed(address(this)));
    }

    function testWithdraw() public {
        assertEq(token.balanceOf(address(distributor)), 1000 ether);
        assertEq(token.balanceOf(owner), 0);

        vm.expectEmit(address(distributor));
        emit TokenDistributor.Withdrawn(owner, 1000 ether);

        vm.prank(owner);
        distributor.withdraw();

        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(token.balanceOf(owner), 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function testInvalidAmount() public {
        vm.expectRevert(abi.encodeWithSelector(TokenDistributor.InvalidAmount.selector));
        distributor.claim(0, new bytes32[](0));
    }

    function testAlreadyClaimed() public {
        bytes32[] memory proof = merkle.getProof(data, 0);

        distributor.claim(1000 ether, proof);

        vm.expectRevert(abi.encodeWithSelector(TokenDistributor.AlreadyClaimed.selector));
        distributor.claim(1000 ether, proof);
    }

    function testEmptyProof() public {
        vm.expectRevert(abi.encodeWithSelector(TokenDistributor.EmptyProof.selector));
        distributor.claim(1000 ether, new bytes32[](0));
    }

    function testInvalidProof() public {
        bytes32[] memory proof = merkle.getProof(data, 0);

        vm.prank(address(0x123));
        vm.expectRevert(abi.encodeWithSelector(TokenDistributor.InvalidProof.selector));
        distributor.claim(1000 ether, proof);
    }

    function testNotEnoughTokens() public {
        bytes32[] memory proof0 = merkle.getProof(data, 0);
        bytes32[] memory proof1 = merkle.getProof(data, 1);

        distributor.claim(1000 ether, proof0);

        vm.prank(address(0x123));
        vm.expectRevert();
        distributor.claim(1000 ether, proof1);
    }

    function testUnauthorizedWithdraw() public {
        vm.expectRevert();
        distributor.withdraw();
    }

    function testInvalidToken() public {
        vm.expectRevert(abi.encodeWithSelector(TokenDistributor.InvalidToken.selector));
        new TokenDistributor(0, address(0), owner);
    }
}

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ScopeKey} from "src/ScopeKey.sol";

contract ScopePackerTest is Test {
    using ScopeKey for bytes24;
    address contractAddress = makeAddr("contractAddress");
    bytes proposedTx = abi.encodeWithSignature("transfer(address,address,uint256)", address(0), address(0), uint256(100));
    bytes4 selector;

    function setUp() public virtual {
        selector = bytes4(proposedTx);
    }

    function test_ScopeKeyPacking() public virtual {
        bytes24 key = ScopeKey._pack(contractAddress, selector);
        (address _contract, bytes4 _selector) = ScopeKey._unpack(key);
        assertEq(contractAddress, _contract);
        assertEq(selector, _selector);
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Validator} from "src/libraries/Validator.sol";
import {IMiddleware} from "src/interfaces/IMiddleware.sol";

contract ValidatorTest is Test {
    address _from = makeAddr("from");
    address _to = makeAddr("to");

    function test_compare_success() public {
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

        Validator.determineValidation(abi.encode(uint256(uint160(_from))), parameters[0], types[0], comparators[0]);
    }

    function test_Revert_InvalidParam_GreaterThan() public {
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

        vm.expectRevert(Validator.InvalidParamRange.selector);
        Validator.determineValidation(abi.encode(uint256(5)), parameters[2], types[2], comparators[2]);
    }

    function test_Revert_InvalidParam_LessThan() public {
        bytes[] memory parameters = new bytes[](3);
        parameters[0] = abi.encode(uint256(uint160(_from)));
        parameters[1] = abi.encode(uint256(uint160(_to)));
        parameters[2] = abi.encode(uint256(10));

        IMiddleware.Comparators[] memory comparators = new IMiddleware.Comparators[](3);

        comparators[0] = IMiddleware.Comparators(0); // EQ
        comparators[1] = IMiddleware.Comparators(0); // EQ
        comparators[2] = IMiddleware.Comparators(1); // LESS THAN

        IMiddleware.SupportedTypes[] memory types = new IMiddleware.SupportedTypes[](3);

        types[0] = IMiddleware.SupportedTypes(7); // address
        types[1] = IMiddleware.SupportedTypes(7); // address
        types[2] = IMiddleware.SupportedTypes(6); // uint256

        vm.expectRevert(Validator.InvalidParamRange.selector);
        Validator.determineValidation(abi.encode(uint256(15)), parameters[2], types[2], comparators[2]);
    }
}

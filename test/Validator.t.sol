// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";
import {Validator} from "src/Validator.sol";

contract ValidatorTest is Test {
    function setUp() public {}

    function testFuzz_validateArbitraryType(uint8 supportedType) public {
        // Just ensure that all enumerated values call their respective functions and skip the comparison
        vm.assume(supportedType < 9);
        IProposalTypesConfigurator.SupportedTypes assignedType =
            IProposalTypesConfigurator.SupportedTypes(supportedType);
        bytes memory paramA = abi.encode("foo");
        bytes memory paramB = abi.encode("bar");

        Validator.determineValidation(paramA, paramB, assignedType, IProposalTypesConfigurator.Comparators(0));
    }
}

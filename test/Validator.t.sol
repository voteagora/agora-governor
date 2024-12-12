// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";
import {Validator} from "src/lib/Validator.sol";

contract ValidatorTest is Test {
    function setUp() public {}

    function testFuzz_validateArbitraryType(uint8 supportedType) public {
        // Just ensure that all enumerated values call their respective functions and skip the comparison
        supportedType = uint8(bound(supportedType, 1, 8));
        IProposalTypesConfigurator.SupportedTypes assignedType =
            IProposalTypesConfigurator.SupportedTypes(supportedType);
        bytes memory paramA = abi.encode(uint256(0));
        bytes memory paramB = abi.encode(uint256(0));

        Validator.determineValidation(paramA, paramB, assignedType, IProposalTypesConfigurator.Comparators(0));
    }
}

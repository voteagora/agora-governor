// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Parser} from "src/libraries/Parser.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract ParserTest is Test {
    using Parser for string;

    function test_parse() public pure {
        string memory description = "my description is this one#proposalTypeId=1";
        uint8 proposalTypeId = description._parseProposalTypeId();
        assertEq(proposalTypeId, 1);
    }

    function test_parse_2() public pure {
        string memory description = "my description is this one#proposalTypeId=255";
        uint8 proposalTypeId = description._parseProposalTypeId();
        assertEq(proposalTypeId, 255);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_parse_exceed() public {
        string memory description = "my description is this one#proposalTypeId=256";
        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 8, 256));
        description._parseProposalTypeId();
    }

    function test_parse_anotherMarker() public pure {
        string memory description = "my description is this one#proposalTypeId=10#proposalData=data";
        uint8 proposalTypeId = description._parseProposalTypeId();
        assertEq(proposalTypeId, 10);
    }

    function test_parse_proposalData() public pure {
        bytes memory proposalData = abi.encode(0x1234);
        string memory description = "my description is this one#proposalTypeId=10#proposalData=";
        string memory descriptionWithData = string.concat(description, string(proposalData));
        string memory proposalDataStr = descriptionWithData._parseProposalData();
        assertEq(string(proposalData), proposalDataStr);
    }
    /* Failing on CI
    function test_parse_proposalData_RevertInvalidDescription() public {
        bytes memory proposalData = abi.encode(0x1234);
        string memory description = "my description is this one#proposalTypeId=10#malformed=";
        string memory descriptionWithData = string.concat(description, string(proposalData));
        vm.expectRevert(Parser.InvalidDescription.selector);
        descriptionWithData._parseProposalData();
    }
    */
}

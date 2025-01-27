// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Parser} from "src/libraries/Parser.sol";

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

    function test_parse_exceed() public {
        string memory description = "my description is this one#proposalTypeId=256";
        vm.expectRevert();
        description._parseProposalTypeId();
    }

    function test_parse_anotherMarker() public pure {
        string memory description = "my description is this one#proposalTypeId=10#proposalData=data";
        uint8 proposalTypeId = description._parseProposalTypeId();
        assertEq(proposalTypeId, 10);
    }
}

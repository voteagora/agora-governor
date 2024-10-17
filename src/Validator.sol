pragma solidity ^0.8.19;

import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";

library Validator {
    error InvalidParamNotEqual();
    error InvalidParamRange();

    function compare(bytes32 paramA, bytes32 paramB, IProposalTypesConfigurator.Comparators comparison) internal pure {
        if (comparison == IProposalTypesConfigurator.Comparators.EQUAL) {
            if (paramA != paramB) revert InvalidParamNotEqual();
        }

        if (comparison == IProposalTypesConfigurator.Comparators.LESS_THAN) {
            if (paramA >= paramB) {
                revert InvalidParamRange();
            }
        }

        if (comparison == IProposalTypesConfigurator.Comparators.GREATER_THAN) {
            if (paramA <= paramB) {
                revert InvalidParamRange();
            }
        }
    }

    function determineValidation(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.SupportedTypes supportedType,
        IProposalTypesConfigurator.Comparators comparison
    ) public pure {
        if (supportedType == IProposalTypesConfigurator.SupportedTypes.UINT8) {
            validate_uint8(param, scopedParam, comparison);
        }

        if (supportedType == IProposalTypesConfigurator.SupportedTypes.UINT16) {
            validate_uint16(param, scopedParam, comparison);
        }

        if (supportedType == IProposalTypesConfigurator.SupportedTypes.UINT32) {
            validate_uint32(param, scopedParam, comparison);
        }

        if (supportedType == IProposalTypesConfigurator.SupportedTypes.UINT64) {
            validate_uint64(param, scopedParam, comparison);
        }

        if (supportedType == IProposalTypesConfigurator.SupportedTypes.UINT128) {
            validate_uint128(param, scopedParam, comparison);
        }

        if (supportedType == IProposalTypesConfigurator.SupportedTypes.UINT256) {
            validate_uint256(param, scopedParam, comparison);
        }

        if (supportedType == IProposalTypesConfigurator.SupportedTypes.ADDRESS) {
            validate_address(param, scopedParam, comparison);
        }

        if (supportedType == IProposalTypesConfigurator.SupportedTypes.BYTES32) {
            validate_bytes32(param, scopedParam, comparison);
        }
    }

    function validate_uint8(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) public pure {
        compare(bytes32(bytes1(param[0:1])), bytes32(bytes1(scopedParam[0:1])), comparison);
    }

    function validate_uint16(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) public pure {
        compare(bytes32(bytes2(param[0:2])), bytes32(bytes2(scopedParam[0:2])), comparison);
    }

    function validate_uint32(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) public pure {
        compare(bytes32(bytes4(param[0:4])), bytes32(bytes4(scopedParam[0:4])), comparison);
    }

    function validate_uint64(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) public pure {
        compare(bytes32(bytes8(param[0:8])), bytes32(bytes8(scopedParam[0:8])), comparison);
    }

    function validate_uint128(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) public pure {
        compare(bytes32(bytes16(param[0:16])), bytes32(bytes16(scopedParam[0:16])), comparison);
    }

    function validate_uint256(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) public pure {
        compare(bytes32(param[0:32]), bytes32(scopedParam[0:32]), comparison);
    }

    function validate_address(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) public pure {
        compare(bytes32(bytes20(param[0:20])), bytes32(bytes20(scopedParam[0:20])), comparison);
    }

    function validate_bytes32(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) public pure {
        compare(bytes32(param[0:32]), bytes32(scopedParam[0:32]), comparison);
    }
}

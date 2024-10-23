pragma solidity ^0.8.19;

import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";

library Validator {
    error InvalidParamNotEqual();
    error InvalidParamRange();

    /**
     * @notice Compares two byte32 values of the represented type and reverts if condition is not met.
     * @param paramA The first parameter, in this case the one extracted from the calldata
     * @param paramB The second parameter, the one stored on the Scope object
     * @param comparison An enumerated type representing which comparison check should be performed
     */
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

    /**
     * @notice Given the types and comparison enumeration, determine which type check to use prior to validation.
     * @param param The parameter extracted from the calldata
     * @param scopedParam The parameter stored on the Scope object
     * @param supportedType An enumerated type representing the possible supported types for size checks
     * @param comparison An enumerated type representing which comparison check should be performed
     */
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

    /**
     * @dev Conforms the uint8 type to the necessary size considerations prior to comparison
     */
    function validate_uint8(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) internal pure {
        compare(bytes32(bytes1(param[0:1])), bytes32(bytes1(scopedParam[0:1])), comparison);
    }

    /**
     * @dev Conforms the uint16 type to the necessary size considerations prior to comparison
     */
    function validate_uint16(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) internal pure {
        compare(bytes32(bytes2(param[0:2])), bytes32(bytes2(scopedParam[0:2])), comparison);
    }

    /**
     * @dev Conforms the uint32 type to the necessary size considerations prior to comparison
     */
    function validate_uint32(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) internal pure {
        compare(bytes32(bytes4(param[0:4])), bytes32(bytes4(scopedParam[0:4])), comparison);
    }

    /**
     * @dev Conforms the uint64 type to the necessary size considerations prior to comparison
     */
    function validate_uint64(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) internal pure {
        compare(bytes32(bytes8(param[0:8])), bytes32(bytes8(scopedParam[0:8])), comparison);
    }

    /**
     * @dev Conforms the uint128 type to the necessary size considerations prior to comparison
     */
    function validate_uint128(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) internal pure {
        compare(bytes32(bytes16(param[0:16])), bytes32(bytes16(scopedParam[0:16])), comparison);
    }

    /**
     * @dev Conforms the uint256 type to the necessary size considerations prior to comparison
     */
    function validate_uint256(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) internal pure {
        compare(bytes32(param[0:32]), bytes32(scopedParam[0:32]), comparison);
    }

    /**
     * @dev Conforms the address type to the necessary size considerations prior to comparison
     */
    function validate_address(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) internal pure {
        compare(bytes32(bytes20(param[0:20])), bytes32(bytes20(scopedParam[0:20])), comparison);
    }

    /**
     * @dev Conforms the bytes32 type to the necessary size considerations prior to comparison
     */
    function validate_bytes32(
        bytes calldata param,
        bytes calldata scopedParam,
        IProposalTypesConfigurator.Comparators comparison
    ) internal pure {
        compare(bytes32(param[0:32]), bytes32(scopedParam[0:32]), comparison);
    }
}

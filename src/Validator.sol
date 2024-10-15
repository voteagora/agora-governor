pragma solidity ^0.8.19;

import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";
import {IAgoraGovernor} from "src/interfaces/IAgoraGovernor.sol";

/**
 * Contract that stores proposalTypes for the Agora Governor.
 */
contract Validator {
    error InvalidParamNotEqual();
    error InvalidParamRange();

    function validate_uint8(bytes calldata param, bytes calldata scopedParam, IProposalTypesConfigurator.Comparators comparison) public {
        uint8 typedParam = uint8(bytes1(param[0:1]));
        uint8 scopedParamTyped = uint8(bytes1(scopedParam[0:1]));

        if (comparison == IProposalTypesConfigurator.Comparators.EQUAL) {
            if (scopedParamTyped != typedParam) revert InvalidParamNotEqual();
        }

        if (comparison == IProposalTypesConfigurator.Comparators.LESS_THAN) {
            if (typedParam >= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }

        if (comparison == IProposalTypesConfigurator.Comparators.GREATER_THAN) {
            if (typedParam <= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }
    }

    function validate_uint16(bytes calldata param, bytes calldata scopedParam, IProposalTypesConfigurator.Comparators comparison) public {
        uint16 typedParam = uint16(bytes2(param[0:2]));
        uint16 scopedParamTyped = uint16(bytes2(scopedParam[0:2]));

        if (comparison == IProposalTypesConfigurator.Comparators.EQUAL) {
            if (scopedParamTyped != typedParam) revert InvalidParamNotEqual();
        }

        if (comparison == IProposalTypesConfigurator.Comparators.LESS_THAN) {
            if (typedParam >= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }

        if (comparison == IProposalTypesConfigurator.Comparators.GREATER_THAN) {
            if (typedParam <= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }
    }

    function validate_uint32(bytes calldata param, bytes calldata scopedParam, IProposalTypesConfigurator.Comparators comparison) public {
        uint32 typedParam = uint32(bytes4(param[0:4]));
        uint32 scopedParamTyped = uint32(bytes4(scopedParam[0:4]));

        if (comparison == IProposalTypesConfigurator.Comparators.EQUAL) {
            if (scopedParamTyped != typedParam) revert InvalidParamNotEqual();
        }

        if (comparison == IProposalTypesConfigurator.Comparators.LESS_THAN) {
            if (typedParam >= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }

        if (comparison == IProposalTypesConfigurator.Comparators.GREATER_THAN) {
            if (typedParam <= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }
    }

    function validate_uint64(bytes calldata param, bytes calldata scopedParam, IProposalTypesConfigurator.Comparators comparison) public {
        uint64 typedParam = uint64(bytes8(param[0:8]));
        uint64 scopedParamTyped = uint64(bytes8(scopedParam[0:8]));

        if (comparison == IProposalTypesConfigurator.Comparators.EQUAL) {
            if (scopedParamTyped != typedParam) revert InvalidParamNotEqual();
        }

        if (comparison == IProposalTypesConfigurator.Comparators.LESS_THAN) {
            if (typedParam >= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }

        if (comparison == IProposalTypesConfigurator.Comparators.GREATER_THAN) {
            if (typedParam <= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }
    }

    function validate_uint128(bytes calldata param, bytes calldata scopedParam, IProposalTypesConfigurator.Comparators comparison) public {
        uint128 typedParam = uint128(bytes16(param[0:16]));
        uint128 scopedParamTyped = uint128(bytes16(scopedParam[0:16]));

        if (comparison == IProposalTypesConfigurator.Comparators.EQUAL) {
            if (scopedParamTyped != typedParam) revert InvalidParamNotEqual();
        }

        if (comparison == IProposalTypesConfigurator.Comparators.LESS_THAN) {
            if (typedParam >= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }

        if (comparison == IProposalTypesConfigurator.Comparators.GREATER_THAN) {
            if (typedParam <= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }
    }

    function validate_uint256(bytes calldata param, bytes calldata scopedParam, IProposalTypesConfigurator.Comparators comparison) public {
        uint256 typedParam = uint256(bytes32(param[0:32]));
        uint256 scopedParamTyped = uint256(bytes32(scopedParam[0:32]));

        if (comparison == IProposalTypesConfigurator.Comparators.EQUAL) {
            if (scopedParamTyped != typedParam) revert InvalidParamNotEqual();
        }

        if (comparison == IProposalTypesConfigurator.Comparators.LESS_THAN) {
            if (typedParam >= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }

        if (comparison == IProposalTypesConfigurator.Comparators.GREATER_THAN) {
            if (typedParam <= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }
    }

    function validate_address(bytes calldata param, bytes calldata scopedParam, IProposalTypesConfigurator.Comparators comparison) public {
        address typedParam = address(bytes20(param[0:20]));
        address scopedParamTyped = address(bytes20(scopedParam[0:20]));

        if (comparison == IProposalTypesConfigurator.Comparators.EQUAL) {
            if (scopedParamTyped != typedParam) revert InvalidParamNotEqual();
        }

        if (comparison == IProposalTypesConfigurator.Comparators.LESS_THAN) {
            if (typedParam >= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }

        if (comparison == IProposalTypesConfigurator.Comparators.GREATER_THAN) {
            if (typedParam <= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }
    }

    function validate_bytes32(bytes calldata param, bytes calldata scopedParam, IProposalTypesConfigurator.Comparators comparison) public {
        bytes32 typedParam = bytes32(param[0:32]);
        bytes32 scopedParamTyped = bytes32(scopedParam[0:32]);

        if (comparison == IProposalTypesConfigurator.Comparators.EQUAL) {
            if (scopedParamTyped != typedParam) revert InvalidParamNotEqual();
        }

        if (comparison == IProposalTypesConfigurator.Comparators.LESS_THAN) {
            if (typedParam >= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }

        if (comparison == IProposalTypesConfigurator.Comparators.GREATER_THAN) {
            if (typedParam <= scopedParamTyped) {
                revert InvalidParamRange();
            }
        }
    }
}


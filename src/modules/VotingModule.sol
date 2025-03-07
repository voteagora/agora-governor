// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @custom:security-contact security@voteagora.com
abstract contract VotingModule {
    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable governor;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotGovernor();
    error ExistingProposal();
    error InvalidParams();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyGovernor() {
        if (msg.sender != governor) revert NotGovernor();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _governor) {
        governor = _governor;
    }

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function propose(uint256 proposalId, bytes memory proposalData, bytes32 descriptionHash) external virtual;

    function _countVote(uint256 proposalId, address account, uint8 support, uint256 weight, bytes memory params)
        external
        virtual;

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _formatExecuteParams(uint256 proposalId, bytes memory proposalData)
        external
        virtual
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas);

    function _voteSucceeded(uint256 proposalId) external view virtual returns (bool);

    /// @notice See {IGovernor-COUNTING_MODE}.
    function COUNTING_MODE() external pure virtual returns (string memory);

    /// @notice Defines the encoding for the expected `proposalData` in `propose`.
    function PROPOSAL_DATA_ENCODING() external pure virtual returns (string memory);

    /// @notice Defines the encoding for the expected `params` in `_countVote`.
    function VOTE_PARAMS_ENCODING() external pure virtual returns (string memory);
}

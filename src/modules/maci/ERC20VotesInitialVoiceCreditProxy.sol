// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {InitialVoiceCreditProxy} from "maci/initialVoiceCreditProxy/InitialVoiceCreditProxy.sol";

/// @title ERC20VotesInitialVoiceCreditProxy
/// @notice This contract allows to set an initial voice credit balance
/// for MACI's voters based on the balance of an ERC20 token at a given block.
contract ERC20VotesInitialVoiceCreditProxy is InitialVoiceCreditProxy {
  /// @notice the block number to be used for the initial voice credits
  uint256 public snapshotBlock;
  /// @notice the token to be used for the initial voice credits
  address public token;
  /// @notice the factor to be used for the initial voice credits
  uint256 public factor;

  /// @notice Initializes the contract.

  constructor(uint256 _snapshotBlock, address _token, uint256 _factor) payable {
    snapshotBlock = _snapshotBlock;
    token = _token;
    factor = _factor;
  }

  /// @notice Returns the constant balance for any new MACI's voter
  /// @return balance
  function getVoiceCredits(address voter, bytes memory) public view override returns (uint256) {
    return IVotes(token).getPastVotes(voter, snapshotBlock) / factor;
  }
}

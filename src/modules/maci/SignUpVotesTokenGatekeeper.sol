// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {SignUpGatekeeper} from "maci/gatekeepers/SignUpGatekeeper.sol";

/// @title SignUpTokenGatekeeper
/// @notice This contract allows to gatekeep MACI signups
/// by requiring new voters to own a certain IVotes token
contract SignUpTokenGatekeeper is SignUpGatekeeper, Ownable(msg.sender) {
    /// @notice the reference to the SignUpToken contract
    IVotes public immutable token;

    /// @notice the reference to the MACI contract
    address public maci;

    mapping(address => bool) public registeredDelegates;

    /// @notice custom errors
    error AlreadyRegistered();
    error ZeroVoiceCredits();
    error OnlyMACI();

    /// @notice creates a new SignUpTokenGatekeeper
    /// @param _token the address of the ERC20 contract
    constructor(address _token) payable {
        token = IVotes(_token);
    }

    /// @notice Adds an uninitialised MACI instance to allow for token signups
    /// @param _maci The MACI contract interface to be stored
    function setMaciInstance(address _maci) public override onlyOwner {
        maci = _maci;
    }

    function register(address _user, bytes memory _data) public override {
        if (maci != msg.sender) revert OnlyMACI();

        uint256 timepoint = abi.decode(_data, (uint256));

        // check the balance of the user at the given snapshot block
        uint256 balance = IVotes(token).getPastVotes(_user, timepoint);
        if (balance < 0) revert ZeroVoiceCredits();

        bool alreadyRegistered = registeredDelegates[_user];
        if (alreadyRegistered) revert AlreadyRegistered();
        registeredDelegates[_user] = true;
    }

    /// @notice Get the trait of the gatekeeper
    /// @return The type of the gatekeeper
    function getTrait() public pure override returns (string memory) {
        return "VotesToken";
    }
}

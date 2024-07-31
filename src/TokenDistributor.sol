// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts-v5/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts-v5/token/ERC20/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts-v5/utils/cryptography/MerkleProof.sol";

contract TokenDistributor is Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a user claims tokens.
     * @param user The user address.
     * @param amount The amount of tokens claimed.
     */
    event Claimed(address indexed user, uint256 amount);

    /**
     * @notice Emitted when the owner withdraws tokens.
     * @param owner The owner address.
     * @param amount The amount of tokens withdrawn.
     */
    event Withdrawn(address indexed owner, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAmount();
    error AlreadyClaimed();
    error InvalidProof();
    error InvalidToken();
    error EmptyProof();

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The merkle root hash.
     */
    bytes32 public immutable MERKLE_ROOT;

    /**
     * @notice The token contract.
     */
    IERC20 public immutable TOKEN;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mapping of claimed status.
     */
    mapping(address user => bool claimed) public hasClaimed;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Define the merkle root, base signer, token and owner.
     * @param _merkleRoot The merkle root hash.
     * @param _token The token address.
     * @param _owner The owner address.
     */
    constructor(bytes32 _merkleRoot, address _token, address _owner) Ownable(_owner) {
        if (_token == address(0)) revert InvalidToken();

        MERKLE_ROOT = _merkleRoot;
        TOKEN = IERC20(_token);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim tokens using a signature and merkle proof.
     * @param amount Amount of tokens to claim.
     * @param merkleProof Merkle proof of claim.
     */
    function claim(uint256 amount, bytes32[] calldata merkleProof) external {
        if (amount == 0) revert InvalidAmount();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();
        if (merkleProof.length == 0) revert EmptyProof();

        // Generate the leaf
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amount))));

        // Verify the merkle proof
        if (!MerkleProof.verify(merkleProof, MERKLE_ROOT, leaf)) revert InvalidProof();

        // Mark as claimed and send the tokens
        hasClaimed[msg.sender] = true;
        TOKEN.transfer(msg.sender, amount);

        emit Claimed(msg.sender, amount);
    }

    /**
     * @notice Withdraw tokens from the contract.
     */
    function withdraw() external onlyOwner {
        uint256 balance = TOKEN.balanceOf(address(this));
        TOKEN.transfer(msg.sender, balance);

        emit Withdrawn(msg.sender, balance);
    }
}

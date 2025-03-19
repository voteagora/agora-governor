// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts-v5/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts-v5/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/contracts-v5/access/Ownable.sol";
import {ERC20Permit, Nonces} from "@openzeppelin/contracts-v5/token/ERC20/extensions/ERC20Permit.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable-v4/utils/math/SafeCastUpgradeable.sol";

contract TokenMock is ERC20, Ownable, ERC20Permit, ERC20Votes {
    constructor(address initialOwner) ERC20("MyToken", "MTK") Ownable(initialOwner) ERC20Permit("MyToken") {}

    using SafeCastUpgradeable for uint256;

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    function clock() public view override returns (uint48) {
        return SafeCastUpgradeable.toUint48(block.timestamp);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }
}

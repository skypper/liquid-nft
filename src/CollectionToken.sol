// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CollectionToken is ERC20, Ownable {
    constructor(string memory name_, string memory symbol_, address owner_) ERC20(name_, symbol_) Ownable(owner_) {}

    function mint(address account, uint256 value) external onlyOwner {
        super._mint(account, value);
    }

    function burn(address account, uint256 value) external onlyOwner {
        super._burn(account, value);
    }
}

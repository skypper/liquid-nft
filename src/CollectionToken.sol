// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * ERC20 token representing a collection of NFTs
 */
contract CollectionToken is ERC20, Ownable {
    constructor(string memory name_, string memory symbol_, address owner_) ERC20(name_, symbol_) Ownable(owner_) {}

    /**
     * Mints new tokens to an account
     *
     * @param account The account to mint tokens to
     * @param value The amount of tokens to mint
     * @dev Only the owner (i.e. Listings account) can mint tokens
     */
    function mint(address account, uint256 value) external onlyOwner {
        super._mint(account, value);
    }

    /**
     * Burns tokens from an account
     *
     * @param account The account to burn tokens from
     * @param value The amount of tokens to burn
     * @dev Only the owner (i.e. Listings account) can burn tokens
     */
    function burn(address account, uint256 value) external onlyOwner {
        super._burn(account, value);
    }
}

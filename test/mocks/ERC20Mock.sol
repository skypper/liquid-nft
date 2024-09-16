// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor() ERC20("ERC20 Mock Token", "MOCK") {}

    function mint(address account, uint256 value) external {
        super._mint(account, value);
    }

    function burn(address account, uint256 value) external {
        super._burn(account, value);
    }
}
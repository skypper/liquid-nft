// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ERC721Mock is ERC721 {
    constructor() ERC721("ERC721 Mock Token", "MOCK") {}

    function mint(address account, uint256 tokenId) external {
        super._mint(account, tokenId);
    }

    function burn(uint256 tokenId) external {
        super._burn(tokenId);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract Listings is ReentrancyGuard, IERC721Receiver {
    struct Listing {
        address collection;
        address tokenId;
        address owner;
    }

    mapping(address collection => mapping(address tokenId => Listing)) listings;

    modifier collectionExists(address collection) {
        _;
    }

    function initializeCollection(address collection, address[] calldata tokenIds) external nonReentrant {}

    function createListing(address collection, address tokenId) external nonReentrant {}

    function cancelListing(address collection, address tokenId) external nonReentrant {}

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

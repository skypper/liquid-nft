// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IListings {
    struct Listing {
        address owner;
    }

    error NotImplemented();
    error CollectionNotExists();
    error NotEnoughNFTs();
    error InvalidReceivers();

    function createCollection(
        string calldata name,
        string calldata symbol,
        address collection,
        uint256[] calldata tokenIds,
        address[] calldata receivers
    ) external;

    function createListing(
        address collection,
        uint256 tokenId,
        address receiver
    ) external;

    function cancelListing(
        address collection,
        uint256 tokenId,
        address receiver
    ) external;
}

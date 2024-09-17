// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IListings {
    struct Listing {
        address owner;
        // uint40 duration;
        // uint40 created;
        // uint16 floorMultiple;
    }
    struct CreateCollection {
        string name;
        string symbol;
        address collection;
        uint256[] tokenIds;
        Listing listing;
    }

    error NotImplemented();
    error CollectionNotExists();
    error NotEnoughNFTs();

    function createCollection(
        CreateCollection calldata createCollection
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

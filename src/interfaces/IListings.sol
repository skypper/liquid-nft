// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IListings {
    struct Listing {
        address owner;
        uint40 duration;
        uint40 created;
        uint16 floorMultiple;
    }
    struct CreateCollection {
        string name;
        string symbol;
        address collection;
        uint256[] tokenIds;
        Listing listing;
    }
    struct CreateListing {
        address collection;
        uint256 tokenId;
        Listing listing;
    }
    struct CancelListing {
        address collection;
        uint256 tokenId;
        address receiver;
    }

    error NotImplemented();
    error CollectionNotExists();
    error NotEnoughNFTs();
    error FloorMultipleTooLow();

    function createCollection(
        CreateCollection calldata _createCollection
    ) external;

    function createListing(
        CreateListing calldata _createListing
    ) external;

    function cancelListing(
        CancelListing calldata _cancelListing
    ) external;
}

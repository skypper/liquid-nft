// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

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

    struct InitializeCollection {
        address collection;
        uint160 sqrtPriceX96;
        uint256 amount0;
        uint256 amount1;
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

    struct FillListing {
        address collection;
        uint256 tokenId;
    }

    error NotImplemented();
    error CollectionNotExists();
    error CollectionExistsAlready();
    error NotEnoughNFTs();
    error NoOwner();
    error DurationTooShort();
    error DurationTooLong();
    error FloorMultipleTooLow();
    error ListingExists();
    error ListingNotExists();
    error Unauthorized();
    error ListingExpired();
    error TaxOverflow();

    function createCollection(CreateCollection calldata _createCollection) external;

    function initializeCollectionETH(InitializeCollection calldata _initializeCollection) external payable;

    function initializeCollection(InitializeCollection calldata _initializeCollection) external;

    function createListing(CreateListing calldata _createListing) external;

    function cancelListing(CancelListing calldata _cancelListing) external;

    function fillListing(FillListing calldata _fillListing) external;

    function isCollection(address collection) external view returns (bool);

    function isListing(address collection, uint256 tokenId) external view returns (bool);

    function getCollectionToken(address collection) external view returns (address);
}

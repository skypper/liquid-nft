// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IListings} from "./interfaces/IListings.sol";
import {CollectionToken} from "./CollectionToken.sol";

contract Listings is IListings, ReentrancyGuard, IERC721Receiver {
    event CollectionCreated(address collection, uint256[] tokenId, Listing listing);

    uint256 public constant BOOTSTRAP_NFTS = 4;

    uint256 public constant MINIMUM_DURATION = 1 days;
    uint256 public constant MAXIMUM_DURATION = 365 days;
    uint256 public constant FLOOR_MULTIPLE_PRECISION = 100;
    uint256 public constant MAXIMUM_FLOOR_MULTIPLE = 500_00;

    mapping(address collection => mapping(uint256 tokenId => Listing)) listings;
    mapping(address collection => bool) collectionCreated;
    mapping(address collection => address collectionToken) collectionTokens;

    modifier collectionExists(address collection) {
        require(collectionCreated[collection], CollectionNotExists());
        _;
    }

    function createCollection(CreateCollection calldata _createCollection) external override nonReentrant {
        require(!collectionCreated[_createCollection.collection], CollectionNotExists());

        require(_createCollection.tokenIds.length >= BOOTSTRAP_NFTS, NotEnoughNFTs());

        uint256 tokenIdsCount = _createCollection.tokenIds.length;
        for (uint256 i; i < tokenIdsCount; ++i) {
            Listing memory listing_ = _createCollection.listing;

            _validateListing(listing_);

            IERC721(_createCollection.collection).safeTransferFrom(
                msg.sender, address(this), _createCollection.tokenIds[i]
            );

            Listing memory listing = Listing({
                owner: listing_.owner,
                duration: listing_.duration,
                created: uint40(block.timestamp),
                floorMultiple: listing_.floorMultiple
            });
            listings[_createCollection.collection][_createCollection.tokenIds[i]] = listing;
        }

        collectionCreated[_createCollection.collection] = true;
        CollectionToken collectionToken =
            new CollectionToken(_createCollection.name, _createCollection.symbol, address(this));
        collectionTokens[_createCollection.collection] = address(collectionToken);

        collectionToken.mint(msg.sender, tokenIdsCount * 1 ether);

        emit CollectionCreated(_createCollection.collection, _createCollection.tokenIds, _createCollection.listing);
    }

    function createListing(CreateListing calldata _createListing)
        external
        override
        nonReentrant
        collectionExists(_createListing.collection)
    {
        Listing memory listing_ = _createListing.listing;
        require(listings[_createListing.collection][_createListing.tokenId].owner == address(0), ListingExists());

        _validateListing(listing_);

        IERC721(_createListing.collection).safeTransferFrom(msg.sender, address(this), _createListing.tokenId);

        Listing memory listing = Listing({
            owner: listing_.owner,
            duration: listing_.duration,
            created: uint40(block.timestamp),
            floorMultiple: listing_.floorMultiple
        });
        listings[_createListing.collection][_createListing.tokenId] = listing;

        address collectionToken = collectionTokens[_createListing.collection];
        CollectionToken(collectionToken).mint(listing_.owner, 1 ether);
    }

    function _validateListing(Listing memory listing) internal pure {
        require(listing.owner != address(0), NoOwner());
        require(listing.duration >= MINIMUM_DURATION, DurationTooShort());
        require(listing.duration <= MAXIMUM_DURATION, DurationTooLong());
        require(listing.floorMultiple >= FLOOR_MULTIPLE_PRECISION, FloorMultipleTooLow());
        require(listing.floorMultiple <= MAXIMUM_FLOOR_MULTIPLE, FloorMultipleTooLow());
    }

    function cancelListing(CancelListing calldata _cancelListing)
        external
        override
        nonReentrant
        collectionExists(_cancelListing.collection)
    {
        require(msg.sender == listings[_cancelListing.collection][_cancelListing.tokenId].owner, Unauthorized());

        address collectionToken = collectionTokens[_cancelListing.collection];
        CollectionToken(collectionToken).burn(msg.sender, 1 ether);

        IERC721(_cancelListing.collection).safeTransferFrom(
            address(this), _cancelListing.receiver, _cancelListing.tokenId
        );
        delete listings[_cancelListing.collection][_cancelListing.tokenId];
    }

    function fillListing(FillListing calldata _fillListing)
        external
        override
        nonReentrant
        collectionExists(_fillListing.collection)
    {
        Listing memory listing = listings[_fillListing.collection][_fillListing.tokenId];
        (bool isAvailable, uint256 price) = _resolveFee(listing);
        require(isAvailable, ListingExpired());

        address collectionToken = collectionTokens[_fillListing.collection];

        uint256 ownerOwed = price - 1 ether;
        // burn the floor price (immediately provided to the listing's owner)
        CollectionToken(collectionToken).burn(msg.sender, 1 ether);
        // transfer the difference upwards from the floor price to the listing's owner
        CollectionToken(collectionToken).transferFrom(msg.sender, listing.owner, ownerOwed);
        // transfer collection NFT to the filler
        IERC721(_fillListing.collection).transferFrom(address(this), msg.sender, _fillListing.tokenId);
    }

    function _resolveFee(Listing memory listing) internal view returns (bool isAvailable, uint256 price) {
        if (listing.created + listing.duration < block.timestamp) {
            return (false, 0);
        }
        price = listing.floorMultiple * 1 ether / FLOOR_MULTIPLE_PRECISION;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

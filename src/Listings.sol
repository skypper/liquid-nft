// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IListings} from "./interfaces/IListings.sol";
import {CollectionToken} from "./CollectionToken.sol";
import {TokenEscrow} from "./TokenEscrow.sol";

contract Listings is IListings, ReentrancyGuard, IERC721Receiver, Ownable, TokenEscrow {
    event CollectionCreated(address collection, uint256[] tokenId, Listing listing);

    uint256 public constant BOOTSTRAP_NFTS = 4;

    uint256 public constant MINIMUM_DURATION = 1 days;
    uint256 public constant MAXIMUM_DURATION = 365 days;
    uint256 public constant FLOOR_MULTIPLE_PRECISION = 100;
    uint256 public constant MAXIMUM_FLOOR_MULTIPLE = 500_00;

    uint256 public constant FEE_PERCENTAGE_PRECISION = 10_000;
    uint256 public feePercentage = 500; // 5%

    mapping(address collection => mapping(uint256 tokenId => Listing)) private listings;
    mapping(address collection => bool) private collectionCreated;
    mapping(address collection => address collectionToken) public collectionTokens;

    modifier collectionExists(address collection) {
        require(collectionCreated[collection], CollectionNotExists());
        _;
    }

    constructor() Ownable(msg.sender) {}

    function createCollection(CreateCollection calldata _createCollection) external override nonReentrant {
        require(!collectionCreated[_createCollection.collection], CollectionNotExists());

        require(_createCollection.tokenIds.length >= BOOTSTRAP_NFTS, NotEnoughNFTs());

        uint256 listingTaxes;
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
            (uint256 listingTax,) = _resolveListingTax(listing);
            listingTaxes += listingTax;
        }

        collectionCreated[_createCollection.collection] = true;
        CollectionToken collectionToken =
            new CollectionToken(_createCollection.name, _createCollection.symbol, address(this));
        collectionTokens[_createCollection.collection] = address(collectionToken);

        uint256 tokensReceived = tokenIdsCount * 1 ether;
        if (tokensReceived < listingTaxes) {
            revert TaxOverflow();
        }
        unchecked {
            tokensReceived -= listingTaxes;
        }
        collectionToken.mint(msg.sender, tokensReceived);

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

        uint256 tokensReceived = 1 ether;
        (uint256 listingTax,) = _resolveListingTax(listing);
        if (tokensReceived < listingTax) {
            revert TaxOverflow();
        }
        unchecked {
            tokensReceived -= listingTax;
        }
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
        Listing memory listing = listings[_cancelListing.collection][_cancelListing.tokenId];
        require(msg.sender == listing.owner, Unauthorized());

        address collectionToken = collectionTokens[_cancelListing.collection];

        (uint256 listingTax, uint256 refund) = _resolveListingTax(listing);

        // deduct the refund from the collected tax
        uint256 collectedTax = listingTax - refund;

        // deduct the refund from the collection token that would be burned from the owner
        uint256 tokensOwed = 1 ether - refund;

        CollectionToken(collectionToken).burn(msg.sender, tokensOwed);
        _deposit(collectionToken, collectedTax, owner());

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
        require(listing.owner != address(0), ListingNotExists());

        (bool isAvailable, uint256 price) = _resolveListingPrice(listing);
        require(isAvailable, ListingExpired());

        (uint256 listingTax, uint256 refund) = _resolveListingTax(listing);
        uint256 taxCollected = listingTax - refund;

        address collectionToken = collectionTokens[_fillListing.collection];

        uint256 ownerOwed = price - 1 ether;

        // transfer the price to the contract
        CollectionToken(collectionToken).transferFrom(msg.sender, address(this), price);

        // burn the floor price (immediately provided to the listing's owner)
        CollectionToken(collectionToken).burn(address(this), 1 ether - refund);

        CollectionToken(collectionToken).transfer(listing.owner, ownerOwed);

        // hold in escrow the tax to be paid to the contract owner (excluding the refund)
        _deposit(collectionToken, taxCollected, owner());

        // hold in escrow the difference upwards from the floor price to the listing's owner
        _deposit(collectionToken, ownerOwed + refund, listing.owner);

        // transfer collection NFT to the filler
        IERC721(_fillListing.collection).transferFrom(address(this), msg.sender, _fillListing.tokenId);

        delete listings[_fillListing.collection][_fillListing.tokenId];
    }

    function transferOwnership(address collection, uint256 tokenId, address newOwner)
        public
        nonReentrant
        collectionExists(collection)
    {
        Listing storage listing = listings[collection][tokenId];
        require(listing.owner != address(0), ListingNotExists());
        require(msg.sender == listing.owner, Unauthorized());
        require(newOwner != address(0), NoOwner());

        listing.owner = newOwner;
    }

    function _resolveListingPrice(Listing memory listing) internal view returns (bool isAvailable, uint256 price) {
        if (listing.created + listing.duration < block.timestamp) {
            return (false, 0);
        }
        price = _getListingPrice(listing);
        isAvailable = true;
    }

    function _resolveListingTax(Listing memory listing) internal view returns (uint256 tax, uint256 refund) {
        uint256 price = _getListingPrice(listing);
        tax = price * feePercentage / FEE_PERCENTAGE_PRECISION;
        if (listing.created + listing.duration < block.timestamp) {
            refund = tax * (listing.created - block.timestamp) / listing.duration;
        }
    }

    function _getListingPrice(Listing memory listing) internal pure returns (uint256 price) {
        price = uint256(listing.floorMultiple) * 1 ether / FLOOR_MULTIPLE_PRECISION;
    }

    function isCollection(address collection) external view override returns (bool) {
        return collectionCreated[collection];
    }

    function isListing(address collection, uint256 tokenId) external view override returns (bool) {
        return listings[collection][tokenId].owner != address(0);
    }

    function ownerOf(address collection, uint256 tokenId) external view returns (address) {
        return listings[collection][tokenId].owner;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

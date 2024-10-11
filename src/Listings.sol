// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IListings} from "./interfaces/IListings.sol";
import {CollectionToken} from "./CollectionToken.sol";
import {TokenEscrow} from "./TokenEscrow.sol";
import {UniswapV4Hook} from "./integrations/UniswapV4Hook.sol";

/**
 * Handles the listings of the NFT marketplace: collection creation, listing creation, listing cancelation, listing filling, listing ownership transfer.
 */
contract Listings is IListings, ReentrancyGuard, IERC721Receiver, Ownable, TokenEscrow {
    // Emitted when a new collection is created
    event CollectionCreated(address indexed collection, uint256[] indexed tokenId, Listing listing);

    // Emitted when a new listing is created
    event ListingCreated(address indexed collection, uint256 indexed tokenId, Listing listing);

    // Emitted when a listing is cancelled
    event ListingCancelled(address indexed collection, uint256 indexed tokenId);

    // Emitted when a listing is filled
    event ListingFilled(address indexed collection, uint256 indexed tokenId, uint256 price);

    // Emitted when on a listing ownership transfer
    event OwnershipTransferred(
        address indexed collection, uint256 indexed tokenId, address indexed oldOwner, address newOwner
    );

    // The minimum number of listings required to create a collection
    uint256 public constant BOOTSTRAP_LISTINGS = 4;

    // The minimum and maximum duration of a listing
    uint256 public constant MINIMUM_DURATION = 1 days;
    uint256 public constant MAXIMUM_DURATION = 365 days;

    // The duration of the Dutch auction after a listing expired
    uint256 public constant EXPIRED_DUTCH_AUCTION_DURATION = 3 days;

    // Parameters for floor prices and multiples
    uint256 public constant FLOOR_MULTIPLE_PRECISION = 100;
    uint256 public constant MAXIMUM_FLOOR_MULTIPLE = 500_00;

    // Parameters for listing fee
    uint256 public constant FEE_PERCENTAGE_PRECISION = 10_000;
    uint256 public feePercentage = 500; // 5%
    uint256 public feeBeneficiarySplit = 5000; // 50% of the fees go to the fee beneficiary

    // The address of the account that receives the fees for the listings (filling, cancelling etc)
    address public feeBeneficiary;

    UniswapV4Hook public uniswapV4Hook;

    // Stores all listings on record
    mapping(address collection => mapping(uint256 tokenId => Listing)) private listings;

    // Mapping for created collections
    mapping(address collection => bool) private collectionCreated;

    // Mapping the corresponding fungible token for a collection
    mapping(address collection => address collectionToken) public collectionTokens;

    /**
     * Helper modifier to prevent the function from being called if the collection does not exist
     */
    modifier collectionExists(address collection) {
        require(collectionCreated[collection], CollectionNotExists());
        _;
    }

    /**
     * Creates a new instance of the Listings contract with the owner initialized as `msg.sender`.
     */
    constructor() Ownable(msg.sender) {
        feeBeneficiary = msg.sender;
    }

    /**
     * Sets the Uniswap V4 hook contract address.
     */
    function setUniswapV4Hook(UniswapV4Hook _uniswapV4Hook) external onlyOwner {
        uniswapV4Hook = _uniswapV4Hook;
    }

    /**
     * Creates a new collection with the given token IDs and listing parameters.
     *
     * @param _createCollection The parameters for the collection creation
     */
    function createCollection(CreateCollection calldata _createCollection) external override nonReentrant {
        require(!collectionCreated[_createCollection.collection], CollectionExistsAlready());

        require(_createCollection.tokenIds.length >= BOOTSTRAP_LISTINGS, NotEnoughNFTs());

        uint256 listingTaxes;
        uint256 tokenIdsCount = _createCollection.tokenIds.length;
        for (uint256 i; i < tokenIdsCount; ++i) {
            Listing calldata listing_ = _createCollection.listing;

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

        uniswapV4Hook.registerCollection(_createCollection.collection);

        uint256 tokensReceived = tokenIdsCount * 1 ether;
        if (tokensReceived < listingTaxes) {
            revert TaxOverflow();
        }
        unchecked {
            tokensReceived -= listingTaxes;
        }
        collectionToken.mint(msg.sender, tokensReceived);

        collectionToken.mint(address(this), listingTaxes);
        collectionToken.approve(address(uniswapV4Hook), listingTaxes);
        uniswapV4Hook.depositFees(_createCollection.collection, 0, listingTaxes);

        emit CollectionCreated(_createCollection.collection, _createCollection.tokenIds, _createCollection.listing);
    }

    /**
     * Creates a new listing for the given collection and token ID.
     * @param _createListing The parameters for the listing creation
     */
    function createListing(CreateListing calldata _createListing)
        external
        override
        nonReentrant
        collectionExists(_createListing.collection)
    {
        Listing calldata listing_ = _createListing.listing;
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

        CollectionToken(collectionToken).mint(address(this), listingTax);
        CollectionToken(collectionToken).approve(address(uniswapV4Hook), listingTax);
        uniswapV4Hook.depositFees(_createListing.collection, 0, listingTax);

        emit ListingCreated(_createListing.collection, _createListing.tokenId, _createListing.listing);
    }

    /**
     * Internal logic for validating a listing. If any of the requirements are not met, the function will revert.
     *
     * @param listing The listing to validate
     */
    function _validateListing(Listing calldata listing) internal pure {
        require(listing.owner != address(0), NoOwner());
        require(listing.duration >= MINIMUM_DURATION, DurationTooShort());
        require(listing.duration <= MAXIMUM_DURATION, DurationTooLong());
        require(listing.floorMultiple >= FLOOR_MULTIPLE_PRECISION, FloorMultipleTooLow());
        require(listing.floorMultiple <= MAXIMUM_FLOOR_MULTIPLE, FloorMultipleTooLow());
    }

    /**
     * Returns the fee split between the fee beneficiary and the LP (liquidity providers).
     *
     * @param fee The total fee to split
     * @return feeBeneficiaryPart The fee beneficiary's part
     * @return feeLPPart The LP's part
     */
    function _feeSplit(uint256 fee) internal view returns (uint256 feeBeneficiaryPart, uint256 feeLPPart) {
        feeBeneficiaryPart = fee * feeBeneficiarySplit / FEE_PERCENTAGE_PRECISION;
        feeLPPart = fee - feeBeneficiaryPart;
    }

    /**
     * Cancels a listing for the given collection and token ID.
     *
     * @param _cancelListing The parameters for the listing cancellation
     */
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

        // settle the fees
        (uint256 feeBeneficiaryPart, uint256 feeLPPart) = _feeSplit(collectedTax);
        // store the collected tax in escrow to be paid to the fee beneficiary
        _deposit(collectionToken, feeBeneficiaryPart, feeBeneficiary);
        // deposit the LP part of the fee to the Uniswap V3 hook
        CollectionToken(collectionToken).approve(address(uniswapV4Hook), feeLPPart);
        uniswapV4Hook.depositFees(_cancelListing.collection, 0, feeLPPart);

        IERC721(_cancelListing.collection).safeTransferFrom(
            address(this), _cancelListing.receiver, _cancelListing.tokenId
        );
        delete listings[_cancelListing.collection][_cancelListing.tokenId];

        emit ListingCancelled(_cancelListing.collection, _cancelListing.tokenId);
    }

    /**
     * Fills a listing for the given collection and token ID.
     *
     * @param _fillListing The parameters for the listing filling
     */
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
        uint256 collectedTax = listingTax - refund;

        address collectionToken = collectionTokens[_fillListing.collection];

        uint256 ownerOwed = price - 1 ether;

        // transfer the price to the contract from the filler
        CollectionToken(collectionToken).transferFrom(msg.sender, address(this), price);

        // burn the floor price (immediately provided to the listing's owner)
        CollectionToken(collectionToken).burn(address(this), 1 ether - refund);

        // transfer the rest of the price to the listing's owner (excluding the floor price which owner immediately received on listing creation)
        CollectionToken(collectionToken).transfer(listing.owner, ownerOwed);

        // hold in escrow the tax to be paid to the fee beneficiary (excluding the refund)
        (uint256 feeBeneficiaryPart, uint256 feeLPPart) = _feeSplit(collectedTax);
        // store the collected tax in escrow to be paid to the fee beneficiary
        _deposit(collectionToken, feeBeneficiaryPart, feeBeneficiary);
        // deposit the LP part of the fee to the Uniswap V3 hook
        CollectionToken(collectionToken).approve(address(uniswapV4Hook), feeLPPart);
        uniswapV4Hook.depositFees(_fillListing.collection, 0, feeLPPart);

        // hold in escrow the difference upwards from the floor price to the listing's owner
        _deposit(collectionToken, ownerOwed + refund, listing.owner);

        // transfer collection NFT to the filler
        IERC721(_fillListing.collection).transferFrom(address(this), msg.sender, _fillListing.tokenId);

        // remove the listing record
        delete listings[_fillListing.collection][_fillListing.tokenId];

        emit ListingFilled(_fillListing.collection, _fillListing.tokenId, price);
    }

    /**
     * Transfers the ownership of a listing to a new owner.
     *
     * @param collection The collection of the listing
     * @param tokenId The token ID of the listing
     * @param newOwner The new owner of the listing
     */
    function transferOwnership(address collection, uint256 tokenId, address newOwner)
        public
        nonReentrant
        collectionExists(collection)
    {
        Listing storage listing = listings[collection][tokenId];
        // cache
        address oldOwner = listing.owner;

        require(listing.owner != address(0), ListingNotExists());
        require(msg.sender == listing.owner, Unauthorized());
        require(newOwner != address(0), NoOwner());

        listing.owner = newOwner;

        emit OwnershipTransferred(collection, tokenId, oldOwner, newOwner);
    }

    /**
     * Internal logic to resolve the availability and price of a listing.
     */
    function _resolveListingPrice(Listing memory listing) internal view returns (bool isAvailable, uint256 price) {
        isAvailable =
            uint256(listing.created) + uint256(listing.duration) + EXPIRED_DUTCH_AUCTION_DURATION >= block.timestamp;
        price = _getListingPrice(listing);
    }

    /**
     * Internal logic to resolve the tax and refund of a listing.
     * The refund is directly proportional to the amount of time left before the listing expires.
     */
    function _resolveListingTax(Listing memory listing) internal view returns (uint256 tax, uint256 refund) {
        uint256 price = _getListingPrice(listing);
        tax = price * feePercentage / FEE_PERCENTAGE_PRECISION;

        uint256 expiresAt = listing.created + listing.duration;
        // if the listing is still active, calculate the refund
        if (expiresAt > block.timestamp) {
            // refund is proportional to the amount of time the listing has left before expiration
            refund = tax * (expiresAt - block.timestamp) / listing.duration;
        }
    }

    /**
     * Internal logic to calculate the price of a listing which is determined by the floor price and the floor multiple.
     * If the listing has expired, the price will decrease linearly over the course of the Dutch auction towards the floor price.
     *
     * @param listing The listing to calculate the price for
     * @return price The price of the listing
     */
    function _getListingPrice(Listing memory listing) internal view returns (uint256 price) {
        uint256 floorPrice = 1 ether;
        price = uint256(listing.floorMultiple) * floorPrice / FLOOR_MULTIPLE_PRECISION;

        uint256 expiresAt = listing.created + listing.duration;
        // if the listing is still active return the price as is
        if (block.timestamp < expiresAt) {
            return price;
        }

        uint256 unavailableAt = expiresAt + EXPIRED_DUTCH_AUCTION_DURATION;
        // if the listing has expired, calculate the price based on the Dutch auction
        if (block.timestamp < unavailableAt) {
            unchecked {
                uint256 remainingPrice = price - floorPrice;
                uint256 remainingTime = unavailableAt - block.timestamp;
                return floorPrice + remainingPrice * remainingTime / EXPIRED_DUTCH_AUCTION_DURATION;
            }
        }
        return floorPrice;
    }

    /**
     * Returns the price of a listing.
     *
     * @param collection The collection of the listing
     * @param tokenId The token ID of the listing
     * @return The price of the listing
     */
    function getListingPrice(address collection, uint256 tokenId) external view returns (uint256) {
        Listing memory listing = listings[collection][tokenId];
        return _getListingPrice(listing);
    }

    /**
     * Returns if the collection exists for supplied address.
     */
    function isCollection(address collection) external view override returns (bool) {
        return collectionCreated[collection];
    }

    /**
     * Returns if the listing exists for the supplied collection and token ID.
     */
    function isListing(address collection, uint256 tokenId) external view override returns (bool) {
        return listings[collection][tokenId].owner != address(0);
    }

    /**
     * Returns the owner of a listing.
     */
    function ownerOf(address collection, uint256 tokenId) external view returns (address) {
        return listings[collection][tokenId].owner;
    }

    /**
     * Returns the address of the collection token for the supplied collection.
     */
    function getCollectionToken(address collection) external view returns (address) {
        return collectionTokens[collection];
    }

    /**
     * Sets the fee percentage for the listings.
     *
     * @param _feeBeneficiary The new fee beneficiary to set
     */
    function setBeneficiary(address _feeBeneficiary) external onlyOwner {
        feeBeneficiary = _feeBeneficiary;
    }

    /**
     * Implement the ERC721 receiver interface to accept NFTs. Do nothing.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {CollectionToken} from "./CollectionToken.sol";

contract Listings is ReentrancyGuard, IERC721Receiver {
    struct Listing {
        address collection;
        uint256 tokenId;
        address owner;
    }

    error NotImplemented();
    error CollectionNotExists();
    error NotEnoughNFTs();
    error InvalidReceivers();

    uint256 constant BOOTSTRAP_NFTS = 3;

    mapping(address collection => mapping(uint256 tokenId => Listing)) listings;
    mapping(address collection => bool) collectionInitialized;
    mapping(address collection => address collectionToken) collectionTokens;

    modifier collectionExists(address collection) {
        require(collectionInitialized[collection], CollectionNotExists());
        _;
    }

    function initializeCollection(address collection, uint256[] calldata tokenIds, address[] calldata receivers) external nonReentrant {
        require(!collectionInitialized[collection], CollectionNotExists());
        
        require(tokenIds.length > BOOTSTRAP_NFTS, NotEnoughNFTs());
        require(tokenIds.length == receivers.length, InvalidReceivers());

        uint256 tokenIdsCount = tokenIds.length;
        for (uint256 i; i < tokenIdsCount; ++i) {
            IERC721(collection).safeTransferFrom(msg.sender, address(this), tokenIds[i]);

            Listing memory listing = Listing(collection, tokenIds[i], receivers[i]);
            listings[collection][tokenIds[i]] = listing;
        }

        collectionInitialized[collection] = true;
        CollectionToken collectionToken = new CollectionToken("", "", address(this));
        collectionTokens[collection] = address(collectionToken);

        collectionToken.mint(msg.sender, tokenIdsCount * 1 ether);
    }

    function createListing(address collection, address tokenId) external nonReentrant collectionExists(collection) {
        revert NotImplemented();
    }

    function cancelListing(address collection, address tokenId) external nonReentrant collectionExists(collection) {
        revert NotImplemented();
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

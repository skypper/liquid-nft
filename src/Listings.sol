// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IListings} from "./interfaces/IListings.sol";
import {CollectionToken} from "./CollectionToken.sol";

contract Listings is IListings, ReentrancyGuard, IERC721Receiver {
    event CollectionCreated(
        address collection,
        uint256[] tokenId,
        address[] receivers
    );

    uint256 constant BOOTSTRAP_NFTS = 3;

    mapping(address collection => mapping(uint256 tokenId => Listing)) listings;
    mapping(address collection => bool) collectionCreated;
    mapping(address collection => address collectionToken) collectionTokens;

    modifier collectionExists(address collection) {
        require(collectionCreated[collection], CollectionNotExists());
        _;
    }

    function createCollection(
        string calldata name,
        string calldata symbol,
        address collection,
        uint256[] calldata tokenIds,
        address[] calldata receivers
    ) external nonReentrant {
        require(!collectionCreated[collection], CollectionNotExists());

        require(tokenIds.length > BOOTSTRAP_NFTS, NotEnoughNFTs());
        require(tokenIds.length == receivers.length, InvalidReceivers());

        uint256 tokenIdsCount = tokenIds.length;
        for (uint256 i; i < tokenIdsCount; ++i) {
            IERC721(collection).safeTransferFrom(
                msg.sender,
                address(this),
                tokenIds[i]
            );

            Listing memory listing = Listing(receivers[i]);
            listings[collection][tokenIds[i]] = listing;
        }

        collectionCreated[collection] = true;
        CollectionToken collectionToken = new CollectionToken(
            name,
            symbol,
            address(this)
        );
        collectionTokens[collection] = address(collectionToken);

        collectionToken.mint(msg.sender, tokenIdsCount * 1 ether);

        emit CollectionCreated(collection, tokenIds, receivers);
    }

    function createListing(
        address collection,
        uint256 tokenId,
        address receiver
    ) external nonReentrant collectionExists(collection) {
        IERC721(collection).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId
        );

        Listing memory listing = Listing(collection);
        listings[collection][tokenId] = listing;

        address collectionToken = collectionTokens[collection];
        CollectionToken(collectionToken).mint(receiver, 1 ether);
    }

    function cancelListing(
        address collection,
        uint256 tokenId,
        address receiver
    ) external nonReentrant collectionExists(collection) {
        address collectionToken = collectionTokens[collection];
        CollectionToken(collectionToken).burn(msg.sender, 1 ether);

        IERC721(collection).safeTransferFrom(address(this), receiver, tokenId);
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

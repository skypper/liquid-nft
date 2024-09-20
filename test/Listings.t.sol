// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Listings} from "../src/Listings.sol";
import {CollectionToken} from "../src/CollectionToken.sol";
import {IListings} from "../src/interfaces/IListings.sol";

import {ERC721Mock} from "./mocks/ERC721Mock.sol";

contract ListingsTest is Test {
    Listings listings;

    ERC721Mock nft1;
    ERC721Mock nft2;
    ERC721Mock nft3;
    ERC721Mock nft4;

    function setUp() public {
        listings = new Listings();

        nft1 = new ERC721Mock();
        nft2 = new ERC721Mock();
        nft3 = new ERC721Mock();
        nft4 = new ERC721Mock();
    }

    function _createCollection(uint256 tokenId, uint256 tokenIdsCount, address receiver) internal {
        uint256[] memory tokenIds = new uint256[](tokenIdsCount);
        IListings.Listing memory listing = IListings.Listing({
            owner: receiver,
            duration: 1 days,
            created: 0,
            floorMultiple: uint16(3 * listings.FLOOR_MULTIPLE_PRECISION())
        });
        for (uint256 i; i < tokenIdsCount; ++i) {
            tokenIds[i] = tokenId + i;

            nft1.mint(receiver, tokenId + i);
        }

        vm.startPrank(receiver);
        nft1.setApprovalForAll(address(listings), true);

        listings.createCollection(
            IListings.CreateCollection("Mock Collection", "CMOCK", address(nft1), tokenIds, listing)
        );
        vm.stopPrank();
    }

    function test_createCollection(uint256 tokenId) public {
        uint256 tokenIdsCount = 4;
        vm.assume(tokenId != 0 && tokenId < type(uint256).max - tokenIdsCount);
        _createCollection(tokenId, tokenIdsCount, address(this));

        assertTrue(listings.isCollection(address(nft1)));
        for (uint256 i; i < tokenIdsCount; ++i) {
            assertTrue(listings.isListing(address(nft1), tokenId + i));
        }
    }

    function test_createCollectionNotEnoughNFTs(uint256 tokenId) public {
        vm.assume(tokenId != 0);

        nft1.mint(address(this), tokenId);

        nft1.setApprovalForAll(address(listings), true);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        IListings.Listing memory listing = IListings.Listing({
            owner: address(this),
            duration: 1 days,
            created: 0,
            floorMultiple: uint16(3 * listings.FLOOR_MULTIPLE_PRECISION())
        });

        vm.expectRevert();
        listings.createCollection(
            IListings.CreateCollection("Mock Collection", "CMOCK", address(nft1), tokenIds, listing)
        );
        assertFalse(listings.isCollection(address(nft1)));
    }

    function test_cancelListingNotAuthorized(uint256 tokenId) public {
        uint256 tokenIdsCount = 4;
        vm.assume(tokenId != 0 && tokenId < type(uint256).max - tokenIdsCount);

        _createCollection(tokenId, tokenIdsCount, makeAddr("user"));

        vm.startPrank(makeAddr("other"));
        IListings.CancelListing memory cancelListing =
            IListings.CancelListing({collection: address(nft1), tokenId: tokenId, receiver: address(this)});
        vm.expectRevert(IListings.Unauthorized.selector);
        listings.cancelListing(cancelListing);
        vm.stopPrank();
    }

    function test_cancelListing(uint256 tokenId) public {
        uint256 tokenIdsCount = 4;
        vm.assume(tokenId != 0 && tokenId < type(uint256).max - tokenIdsCount);

        address user = makeAddr("user");

        _createCollection(tokenId, tokenIdsCount, user);

        IListings.CancelListing memory cancelListing =
            IListings.CancelListing({collection: address(nft1), tokenId: tokenId, receiver: user});

        address collectionToken = listings.collectionTokens(address(nft1));

        vm.startPrank(user);
        CollectionToken(collectionToken).approve(address(listings), 1 ether);
        listings.cancelListing(cancelListing);
        vm.stopPrank();
    }
}

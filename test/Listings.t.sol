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

    function test_fillListing(uint256 tokenId) public {
        uint256 tokenIdsCount = 4;
        vm.assume(tokenId != 0 && tokenId < type(uint256).max - tokenIdsCount);

        address user = makeAddr("user");

        _createCollection(tokenId, tokenIdsCount, user);

        address otherUser = makeAddr("other");
        address collectionToken = listings.collectionTokens(address(nft1));
        deal(collectionToken, otherUser, 3 ether);
        vm.startPrank(otherUser);
        CollectionToken(collectionToken).approve(address(listings), 3 ether);
        IListings.FillListing memory fillListing = IListings.FillListing({collection: address(nft1), tokenId: tokenId});
        listings.fillListing(fillListing);
        vm.stopPrank();

        assertEq(CollectionToken(collectionToken).balanceOf(otherUser), 0);
        assertFalse(listings.isListing(address(nft1), tokenId));
    }

    function testFail_fillListingListingExpired(uint256 tokenId) public {
        uint256 tokenIdsCount = 4;
        vm.assume(tokenId != 0 && tokenId < type(uint256).max - tokenIdsCount);

        address user = makeAddr("user");

        _createCollection(tokenId, tokenIdsCount, user);

        vm.startPrank(user);
        address collectionToken = listings.collectionTokens(address(nft1));
        deal(collectionToken, user, 3 ether);

        CollectionToken(collectionToken).approve(address(listings), 3 ether);
        IListings.FillListing memory fillListing = IListings.FillListing({collection: address(nft1), tokenId: tokenId});
        // roll time forward by 1 day to cause the listing to expire
        vm.warp(block.timestamp + 1 days + 3 days + 1);
        listings.fillListing(fillListing);
        vm.stopPrank();
    }

    function testFail_fillListingInsufficientTokens(uint256 tokenId) public {
        uint256 tokenIdsCount = 4;
        vm.assume(tokenId != 0 && tokenId < type(uint256).max - tokenIdsCount);

        address user = makeAddr("user");

        _createCollection(tokenId, tokenIdsCount, user);

        vm.startPrank(user);
        address collectionToken = listings.collectionTokens(address(nft1));
        deal(collectionToken, user, 2 ether); // not enough funds, the price is 3 ether

        CollectionToken(collectionToken).approve(address(listings), 2 ether);
        IListings.FillListing memory fillListing = IListings.FillListing({collection: address(nft1), tokenId: tokenId});
        listings.fillListing(fillListing);
        vm.stopPrank();
    }

    function test_listingPricingCorrectness(uint256 tokenId) public {
        uint256 tokenIdsCount = 4;
        vm.assume(tokenId != 0 && tokenId < type(uint256).max - tokenIdsCount);

        address user = makeAddr("user");

        _createCollection(tokenId, tokenIdsCount, user);

        assertEq(listings.getListingPrice(address(nft1), tokenId), 3 ether);
        vm.warp(block.timestamp + 0.5 days);
        assertEq(listings.getListingPrice(address(nft1), tokenId), 3 ether);

        vm.warp(block.timestamp + 0.5 days);
        assertEq(listings.getListingPrice(address(nft1), tokenId), 3 ether);

        console.log("EXPIRED");

        // the listing expires after 1 day; the dutch auction starts at 3 ether and decreases until 1 ether for 3 days
        // given that the price is 3 ether and the floor is 1 ether, 2 ether is evenly spaces out during those 3 days
        // 6 evenly distributed points over 3 days is 1 point every 12 hours, so the price should decrease by 0.333 ether every 12 hours
        uint256 points = 6;
        for (uint256 i; i < points; ++i) {
            vm.warp(block.timestamp + 3 days / 6);
            assertApproxEqRel(listings.getListingPrice(address(nft1), tokenId), 3 ether - 0.333 ether * (i + 1), 0.01 ether);
        }
    }

    function test_transferOwnership(uint256 tokenId) public {
        uint256 tokenIdsCount = 4;
        vm.assume(tokenId != 0 && tokenId < type(uint256).max - tokenIdsCount);

        address user = makeAddr("user");

        _createCollection(tokenId, tokenIdsCount, user);

        address newOwner = makeAddr("newOwner");

        assertTrue(listings.ownerOf(address(nft1), tokenId) == user);
        vm.prank(user);
        address collection = address(nft1);
        listings.transferOwnership(collection, tokenId, newOwner);
        assertTrue(listings.ownerOf(address(nft1), tokenId) == newOwner);
    }
}

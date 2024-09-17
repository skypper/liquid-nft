// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Listings} from "../src/Listings.sol";

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

    function test_createCollection(uint256 tokenId) public {
        vm.assume(tokenId != 0 && tokenId < type(uint256).max - 4);
        uint256[] memory tokenIds = new uint256[](4);
        address[] memory receivers = new address[](4);
        for (uint256 i; i < 4; ++i) {
            tokenIds[i] = tokenId + i;
            receivers[i] = address(this);

            nft1.mint(address(this), tokenId + i);
        }

        nft1.setApprovalForAll(address(listings), true);
        
        listings.createCollection("Mock Collection", "CMOCK", address(nft1), tokenIds, receivers);
    }

    function test_createCollectionNotEnoughNFTs(uint256 tokenId) public {
        vm.assume(tokenId != 0);

        nft1.mint(address(this), tokenId);

        nft1.setApprovalForAll(address(listings), true);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        address[] memory receivers = new address[](1);
        receivers[0] = address(this);
        
        vm.expectRevert();
        listings.createCollection("Mock Collection", "CMOCK", address(nft1), tokenIds, receivers);
    }
}

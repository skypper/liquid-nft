// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Listings} from "../src/Listings.sol";

import {ERC721Mock} from "./mocks/ERC721Mock.sol";

contract ListingsTest is Test {
    Listings listings;
    ERC721Mock nft1;

    function setUp() public {
        listings = new Listings();

        nft1 = new ERC721Mock();
    }

    function test_createCollectionNotEnoughNFTs(uint256 tokenId) public {
        nft1.mint(address(this), tokenId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        address[] memory receivers = new address[](1);
        receivers[0] = address(this);
        
        vm.expectRevert();
        listings.createCollection("Mock Collection", "CMOCK", address(nft1), tokenIds, receivers);
    }
}

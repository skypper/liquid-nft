// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/Test.sol";

import {LiquidNFTTest} from "./utils/LiquidNFTTest.sol";

contract UniswapV4HookTest is LiquidNFTTest {
    function test_addLiquidity(uint256 tokenId) public {
        uint256 tokenIdsCount = 4;
        vm.assume(tokenId != 0 && tokenId < type(uint256).max - tokenIdsCount);

        address user = makeAddr("user");

        _createCollection(tokenId, tokenIdsCount, user);

        address collectionToken = listings.getCollectionToken(address(nft1));
        deal(address(nativeToken), address(uniswapV4Hook), 1 ether);
        deal(collectionToken, address(uniswapV4Hook), 1 ether);

        vm.prank(address(listings));
        uniswapV4Hook.initializeCollection(address(nft1), 45765206694984738996961730 / 60 * 60, 1 ether, 1 ether);
    }
}

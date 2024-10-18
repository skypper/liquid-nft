// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/Test.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {LiquidNFTTest} from "./utils/LiquidNFTTest.sol";
import {CollectionToken} from "../src/CollectionToken.sol";

contract UniswapV4HookTest is LiquidNFTTest {
    using PoolIdLibrary for PoolKey;

    function test_addLiquidity(uint256 tokenId) public {
        uint256 tokenIdsCount = 4;
        vm.assume(tokenId != 0 && tokenId < type(uint256).max - tokenIdsCount);

        address user = makeAddr("user");

        _createCollection(tokenId, tokenIdsCount, user);

        PoolKey memory poolKey = uniswapV4Hook.getPoolKey(address(nft1));
        PoolId poolId = poolKey.toId();

        // test that pool is uninitialized
        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(poolId);
        assertTrue(sqrtPriceX96 == 0);

        // test that there is no liquidity in the pool
        assertTrue(stateView.getLiquidity(poolId) == 0);

        address collectionToken = listings.getCollectionToken(address(nft1));
        deal(address(nativeToken), address(listings), 1 ether);
        deal(collectionToken, address(listings), 1 ether);

        vm.startPrank(address(listings));
        nativeToken.approve(address(uniswapV4Hook), 1 ether);
        CollectionToken(collectionToken).approve(address(uniswapV4Hook), 1 ether);

        uniswapV4Hook.initializeCollection(address(nft1), LiquidNFTTest.DUMMY_SQRT_PRICE, 1 ether, 1 ether);
        vm.stopPrank();

        // test that pool has been initialized
        (sqrtPriceX96,,,) = stateView.getSlot0(poolId);
        assertTrue(sqrtPriceX96 > 0);

        // test that liquidity has been minted
        assertTrue(stateView.getLiquidity(poolId) > 0);
    }

    function testFail_initializeNotHook(uint256 tokenId) public {
        uint256 tokenIdsCount = 4;
        vm.assume(tokenId != 0 && tokenId < type(uint256).max - tokenIdsCount);

        address user = makeAddr("user");

        _createCollection(tokenId, tokenIdsCount, user);

        PoolKey memory poolKey = uniswapV4Hook.getPoolKey(address(nft1));
        PoolId poolId = poolKey.toId();

        poolManager.initialize(poolKey, LiquidNFTTest.DUMMY_SQRT_PRICE, "");
    }
}

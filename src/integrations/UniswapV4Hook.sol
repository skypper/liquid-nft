// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import {BalanceDelta} from "v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-periphery/lib/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";

import {IListings} from "../interfaces/IListings.sol";
import {CollectionToken} from "../CollectionToken.sol";

import {console} from "forge-std/Test.sol";

contract UniswapV4Hook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    error CallerIsNotListings();

    IListings public listings;
    IERC20 public nativeToken;

    // default pool parameters
    uint24 constant DEFAULT_POOL_FEE = 3000; // 0.3%
    int24 constant DEFAULT_POOL_TICK_SPACING = 60;

    // only pool owner can change the pool fee
    struct PoolInfo {
        PoolKey key;
        bool currencyFlipped;
        bool initialized;
        uint256 poolFee;
    }

    // Holds the pool key for a collection
    mapping(address collection => PoolKey) public poolKeys;

    // Holds the pool info for a pool
    // @dev poolId is the key and is obtained from `PoolKey`
    mapping(PoolId => PoolInfo) public poolInfos;

    constructor(IListings _listings, IERC20 _nativeToken, IPoolManager _poolManager) BaseHook(_poolManager) {
        listings = _listings;
        nativeToken = _nativeToken;
    }

    modifier onlyListings() {
        require(msg.sender == address(listings), CallerIsNotListings());
        _;
    }

    function registerCollection(address collection) external onlyListings {
        require(poolKeys[collection].fee == 0, "Collection already registered");

        address collectionToken = listings.getCollectionToken(collection);

        bool currencyFlipped = address(nativeToken) > collectionToken;
        PoolKey memory poolKey = PoolKey({
            currency0: currencyFlipped ? Currency.wrap(collectionToken) : Currency.wrap(address(nativeToken)),
            currency1: currencyFlipped ? Currency.wrap(address(nativeToken)) : Currency.wrap(collectionToken),
            fee: DEFAULT_POOL_FEE,
            tickSpacing: 60,
            hooks: IHooks(address(this))
        });
        poolKeys[collection] = poolKey;

        poolInfos[poolKey.toId()] =
            PoolInfo({key: poolKey, currencyFlipped: currencyFlipped, initialized: false, poolFee: 0});
    }

    function initializeCollection(address collection, uint256 tokenId, uint160 sqrtPriceX96) external onlyListings {
        PoolKey memory poolKey = poolKeys[collection];
        PoolInfo storage poolInfo = poolInfos[poolKey.toId()];

        // require(!listings.isCollection(collection), "Collection not registered");
        require(poolInfo.initialized == false, "Collection already initialized");

        address collectionToken = listings.getCollectionToken(collection);

        poolManager.initialize(poolKey, sqrtPriceX96, "");
        
        poolManager.unlock(abi.encodeCall(UniswapV4Hook.addLiquidity, (collection)));

        poolInfo.initialized = true;
    }

    function addLiquidity(address collection) external {
        console.log("XX add liquidity", collection);

        Currency.wrap(address(nativeToken)).settle(poolManager, msg.sender, 1 ether, false);
        Currency.wrap(address(listings.getCollectionToken(collection))).take(poolManager, msg.sender, 1 ether, false);

    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeInitialize(address, PoolKey calldata, uint160, bytes calldata) external override returns (bytes4) {
        return this.beforeInitialize.selector;
    }
}

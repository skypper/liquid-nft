// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import {BalanceDelta, toBalanceDelta} from "v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-periphery/lib/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {TickMath} from "v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import {SafeCast} from "v4-periphery/lib/v4-core/src/libraries/SafeCast.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {console} from "forge-std/Test.sol";

import {IListings} from "../interfaces/IListings.sol";
import {CollectionToken} from "../CollectionToken.sol";

import {console} from "forge-std/Test.sol";

/**
 * This is a singleton hook contract that is attached to every pool within the Liquid NFT system
 * and supported natively (i.e. pool creation, liquidity provision etc. performed as part of the protocol).
 * Thus, the hook becomes the middleman that initializes a pool and adds liquidity to it on behalf of the user
 * when a new collection is created.
 * The hook also distributes a part of the accrued protocol fees to the liquidity providers.
 *
 * @dev This hook is used to initialize the pool and add liquidity to it when a new collection is created.
 * @dev This hook is used to distribute the accrued fees to the pool owner.
 */
contract UniswapV4Hook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using SafeCast for *;

    error CallerIsNotListings();
    error CollectionAlreadyInitialized();
    error HookInvalidSender();

    IListings public listings;
    IERC20 public nativeToken;

    // default pool parameters
    uint24 constant DEFAULT_POOL_FEE = 3000; // 0.3%
    int24 constant DEFAULT_POOL_TICK_SPACING = 60;
    uint256 constant MINIMUM_DONATE_AMOUNT = 0.0001 ether;

    // only pool owner can change the pool fee
    struct PoolInfo {
        PoolKey key;
        // @notice `currency0` is always the native token and `currency1` is always the collection token inside the hook metadata,
        // @notice which could differ from UniswapV4 pool order (i.e. iff `currency0` > `currency1`).
        bool currencyFlipped;
        bool initialized;
        uint256 poolFee;
    }

    // Holds the pool key for a collection
    mapping(address collection => PoolKey) public poolKeys;

    struct AccruedFees {
        // denominates native tokens
        uint256 amount0;
        // denominates collection token always
        uint256 amount1;
    }

    // Holds the accrued fees for a pool
    mapping(PoolId => AccruedFees) public poolFees;

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

    function initializeCollection(address collection, uint160 sqrtPriceX96, uint256 amount0, uint256 amount1)
        external
        onlyListings
    {
        PoolKey memory poolKey = poolKeys[collection];
        require(listings.isCollection(collection), IListings.CollectionNotExists());

        PoolInfo storage poolInfo = poolInfos[poolKey.toId()];
        require(poolInfo.initialized == false, CollectionAlreadyInitialized());

        poolManager.initialize(poolKey, sqrtPriceX96, "");

        nativeToken.transferFrom(msg.sender, address(this), amount0);

        address collectionToken = listings.getCollectionToken(collection);
        CollectionToken(collectionToken).transferFrom(msg.sender, address(this), amount1);

        poolManager.unlock(abi.encodeCall(UniswapV4Hook.addLiquidity, (poolKey, sqrtPriceX96, amount0, amount1)));

        poolInfo.initialized = true;
    }

    function addLiquidity(PoolKey memory poolKey, uint160 sqrtPriceX96, uint256 amount0, uint256 amount1)
        external
        returns (bytes memory)
    {
        int24 lowerTick = TickMath.minUsableTick(DEFAULT_POOL_TICK_SPACING);
        int24 upperTick = TickMath.maxUsableTick(DEFAULT_POOL_TICK_SPACING);
        uint160 sqrtPriceAX96 = TickMath.getSqrtPriceAtTick(lowerTick);
        uint160 sqrtPriceBX96 = TickMath.getSqrtPriceAtTick(upperTick);
        uint128 liquidityToAdd = LiquidityAmounts.getLiquidityForAmounts({
            sqrtPriceX96: sqrtPriceX96,
            sqrtPriceAX96: sqrtPriceAX96,
            sqrtPriceBX96: sqrtPriceBX96,
            amount0: amount0,
            amount1: amount1
        });

        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: lowerTick,
                tickUpper: upperTick,
                liquidityDelta: liquidityToAdd.toInt256(),
                salt: ""
            }),
            ""
        );

        if (delta.amount0() < 0) {
            poolKey.currency0.settle(poolManager, msg.sender, uint128(-delta.amount0()), false);
        }
        if (delta.amount1() < 0) {
            poolKey.currency1.settle(poolManager, msg.sender, uint128(-delta.amount1()), false);
        }
        return abi.encode(toBalanceDelta(1 ether, 1 ether));
    }

    function depositFees(address collection, uint256 amount0, uint256 amount1) external {
        IERC20(nativeToken).transferFrom(msg.sender, address(this), amount0);

        address collectionToken = listings.getCollectionToken(collection);
        CollectionToken(collectionToken).transferFrom(msg.sender, address(this), amount1);

        PoolId poolId = poolKeys[collection].toId();
        poolFees[poolId].amount0 += amount0;
        poolFees[poolId].amount1 += amount1;
    }

    function beforeInitialize(address sender, PoolKey calldata, uint160, bytes calldata)
        external
        view
        override
        returns (bytes4)
    {
        // @dev pool must be initialized by the hook by calling `initializeCollection` function
        require(sender == address(this), HookInvalidSender());
        return this.beforeInitialize.selector;
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata poolKey,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        _distributeFees(poolKey);
        return this.beforeAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata poolKey,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        _distributeFees(poolKey);
        return this.beforeRemoveLiquidity.selector;
    }

    function afterSwap(
        address,
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        _distributeFees(poolKey);
        return (this.afterSwap.selector, 0);
    }

    function _distributeFees(PoolKey memory poolKey) internal {
        PoolId poolId = poolKey.toId();
        PoolInfo memory poolInfo = poolInfos[poolId];
        AccruedFees storage accruedFees = poolFees[poolId];

        uint256 accruedNativeTokens = accruedFees.amount0;
        accruedFees.amount0 = 0;

        if (accruedNativeTokens < MINIMUM_DONATE_AMOUNT) {
            return;
        }

        (uint256 amount0, uint256 amount1) =
            poolInfo.currencyFlipped ? (uint256(0), accruedNativeTokens) : (accruedNativeTokens, uint256(0));
        BalanceDelta delta = poolManager.donate(poolKey, amount0, amount1, "");

        if (delta.amount0() < 0) {
            poolKey.currency0.settle(poolManager, address(this), uint128(-delta.amount0()), false);
        }
        if (delta.amount1() < 0) {
            poolKey.currency1.settle(poolManager, address(this), uint128(-delta.amount1()), false);
        }
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function getPoolKey(address collection) external view returns (PoolKey memory) {
        return poolKeys[collection];
    }
}

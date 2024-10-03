// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import {BalanceDelta} from "v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-periphery/lib/v4-core/src/types/BeforeSwapDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {IListings} from "../interfaces/IListings.sol";

contract UniswapV4Hook is BaseHook {
    error CallerIsNotListings();

    IListings public listings;
    IERC20 public nativeToken;
    struct Pool {
        PoolKey key;
        uint256 tokenId;
        uint256 tokenIdsCount;
        address receiver;
    }

    constructor(IListings _listings, IERC20 _nativeToken, IPoolManager _poolManager) BaseHook(_poolManager) {
        listings = _listings;
        nativeToken = _nativeToken;
    }

    modifier onlyListings() {
        require(msg.sender == address(listings), CallerIsNotListings());
        _;
    }
    
    function registerCollection() external onlyListings {
        throw "Unimplemented";
    }

    function initializeCollection() external onlyListings {
        throw "Unimplemented";
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

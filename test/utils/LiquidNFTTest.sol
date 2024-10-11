// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-template/test/utils/HookMiner.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {Listings} from "../../src/Listings.sol";
import {IListings} from "../../src/interfaces/IListings.sol";
import {CollectionToken} from "../../src/CollectionToken.sol";
import {UniswapV4Hook} from "../../src/integrations/UniswapV4Hook.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {ERC721Mock} from "../mocks/ERC721Mock.sol";

contract LiquidNFTTest is Test {
    Listings listings;

    UniswapV4Hook uniswapV4Hook;

    ERC20Mock nativeToken;
    PoolManager poolManager;

    ERC721Mock nft1;
    ERC721Mock nft2;
    ERC721Mock nft3;
    ERC721Mock nft4;

    function setUp() public {
        listings = new Listings();

        poolManager = new PoolManager();
        nativeToken = new ERC20Mock();

        address deployer = makeAddr("deployer");

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                | Hooks.AFTER_SWAP_FLAG
        );

        bytes memory constructorArgs = abi.encode(listings, nativeToken, poolManager);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(deployer, flags, type(UniswapV4Hook).creationCode, constructorArgs);

        vm.startPrank(deployer);

        uniswapV4Hook =
            new UniswapV4Hook{salt: salt}(IListings(listings), IERC20(nativeToken), IPoolManager(poolManager));
        require(address(uniswapV4Hook) == hookAddress, "Hook address mismatch");

        vm.stopPrank();

        listings.setUniswapV4Hook(uniswapV4Hook);

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

        // Confirm that the expected event is fired
        vm.expectEmit();
        emit Listings.CollectionCreated(address(nft1), tokenIds, listing);

        listings.createCollection(
            IListings.CreateCollection("Mock Collection", "CMOCK", address(nft1), tokenIds, listing)
        );
        vm.stopPrank();
    }
}

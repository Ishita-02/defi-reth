// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {IRETH} from "@src/interfaces/rocket-pool/IRETH.sol";
import {IERC20} from "@src/interfaces/IERC20.sol";
import {ISwapRouter} from "@src/interfaces/uniswap/ISwapRouter.sol";
import {
    RETH,
    WETH,
    UNISWAP_V3_SWAP_ROUTER_02,
    UNISWAP_V3_POOL_FEE_RETH_WETH
} from "@src/Constants.sol";
import {SwapUniswapV3} from "@src/exercises/SwapUniswapV3.sol";

// forge test --fork-url $FORK_URL --match-path test/exercise-swap-uniswap-v3.sol -vvv

contract UniswapV3SwapTest is Test {
    IRETH constant reth = IRETH(RETH);
    IERC20 constant weth = IERC20(WETH);
    SwapUniswapV3 swap;

    function setUp() public {
        swap = new SwapUniswapV3();
    }

    function test_swapWethToReth() public {
        uint256 wethAmount = 1e18;
        deal(WETH, address(this), wethAmount);
        weth.approve(address(swap), wethAmount);

        swap.swapWethToReth(wethAmount, 1);

        uint256 rEthBal = reth.balanceOf(address(swap));
        console.log("rETH balance %e", rEthBal);

        assertGt(rEthBal, 0);
        assertEq(weth.balanceOf(address(swap)), 0);
    }

    function test_swapRethToWeth() public {
        uint256 rEthAmount = 1e18;
        deal(RETH, address(this), rEthAmount);
        reth.approve(address(swap), rEthAmount);

        swap.swapRethToWeth(rEthAmount, 1);

        uint256 wethBal = weth.balanceOf(address(swap));
        console.log("WETH balance %e", wethBal);

        assertGt(wethBal, 0);
        assertEq(reth.balanceOf(address(swap)), 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {IRETH} from "@src/interfaces/rocket-pool/IRETH.sol";
import {IERC20} from "@src/interfaces/IERC20.sol";
import {IRocketDepositPool} from
    "@src/interfaces/rocket-pool/IRocketDepositPool.sol";
import {ISwapRouter} from "@src/interfaces/uniswap/ISwapRouter.sol";
import {
    RETH,
    WETH,
    ROCKET_DEPOSIT_POOL,
    UNISWAP_V3_SWAP_ROUTER_02,
    UNISWAP_V3_POOL_FEE_RETH_WETH
} from "@src/Constants.sol";
import {SwapUniswapV3} from "@src/solutions/SwapUniswapV3.sol";

// forge test --fork-url $FORK_URL --match-path test/dev-reth-uniswap-v3-arb.sol -vvv

contract RethUniswapArb is Test {
    IRETH constant reth = IRETH(RETH);
    IERC20 constant weth = IERC20(WETH);
    IRocketDepositPool internal constant depositPool =
        IRocketDepositPool(ROCKET_DEPOSIT_POOL);
    ISwapRouter public constant router = ISwapRouter(UNISWAP_V3_SWAP_ROUTER_02);

    function test_arb_rocket_pool_to_uni_v3() public {
        depositPool.deposit{value: 1e18}();

        uint256 rEthBal = reth.balanceOf(address(this));

        reth.approve(address(router), rEthBal);
        uint256 wethAmount = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: RETH,
                tokenOut: WETH,
                fee: UNISWAP_V3_POOL_FEE_RETH_WETH,
                recipient: address(this),
                amountIn: rEthBal,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            })
        );

        console.log("WETH %e", wethAmount);
    }

    receive() external payable {}

    function test_arb_uni_v3_to_rocket_pool() public {
        // Make sure depositPool has sufficient ETH
        (bool ok,) = RETH.call{value: 10 * 1e18}("");
        require(ok, "Send ETH failed");

        uint256 wethBal = 1e18;
        deal(address(weth), address(this), wethBal);

        weth.approve(address(router), wethBal);
        uint256 rethAmount = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: RETH,
                fee: UNISWAP_V3_POOL_FEE_RETH_WETH,
                recipient: address(this),
                amountIn: wethBal,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 ethBalBefore = address(this).balance;
        reth.burn(rethAmount);
        uint256 ethBalAfter = address(this).balance;

        console.log("WETH %e", ethBalAfter - ethBalBefore);
    }
}

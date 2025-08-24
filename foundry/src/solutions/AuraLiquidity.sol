// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "../interfaces/IERC20.sol";
import {IRETH} from "../interfaces/rocket-pool/IRETH.sol";
import {IVault} from "../interfaces/balancer/IVault.sol";
import {IRewardPoolDepositWrapper} from
    "../interfaces/aura/IRewardPoolDepositWrapper.sol";
import {IBaseRewardPool4626} from "../interfaces/aura/IBaseRewardPool4626.sol";
import {
    WETH,
    RETH,
    BAL,
    BALANCER_VAULT,
    BALANCER_POOL_ID_RETH_WETH,
    BALANCER_POOL_RETH_WETH,
    AURA,
    AURA_REWARD_POOL_DEPOSIT_WRAPPER,
    AURA_BASE_REWARD_POOL_4626_RETH
} from "../Constants.sol";

/// @title AuraLiquidity
/// @notice This contract allows the deposit and withdrawal of liquidity in the Aura protocol,
//          along with reward claiming.
/// @dev The contract interacts with RocketPool, Balancer, and Aura protocols for
//       liquidity provision and reward management.
contract AuraLiquidity {
    IRETH private constant reth = IRETH(RETH);
    IERC20 private constant weth = IERC20(WETH);
    IERC20 private constant bal = IERC20(BAL);
    IERC20 private constant aura = IERC20(AURA);
    IVault private constant vault = IVault(BALANCER_VAULT);
    IERC20 private constant bpt = IERC20(BALANCER_POOL_RETH_WETH);

    IRewardPoolDepositWrapper private constant depositWrapper =
        IRewardPoolDepositWrapper(AURA_REWARD_POOL_DEPOSIT_WRAPPER);
    IBaseRewardPool4626 private constant rewardPool =
        IBaseRewardPool4626(AURA_BASE_REWARD_POOL_4626_RETH);

    address public owner;

    modifier auth() {
        require(msg.sender == owner, "not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Deposit RETH into the Balancer liquidity pool through Aura
    /// @param rethAmount The amount of RETH to deposit
    /// @return shares The number of LP shares received
    /// @dev This function deposits RETH into the Balancer liquidity pool through Aura
    function deposit(uint256 rethAmount) external returns (uint256 shares) {
        reth.transferFrom(msg.sender, address(this), rethAmount);
        reth.approve(address(depositWrapper), rethAmount);

        // Tokens must be ordered numerically by token address
        address[] memory assets = new address[](2);
        assets[0] = RETH;
        assets[1] = WETH;

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = rethAmount;
        maxAmountsIn[1] = 0;

        depositWrapper.depositSingle({
            rewardPool: address(rewardPool),
            inputToken: RETH,
            inputAmount: rethAmount,
            balancerPoolId: BALANCER_POOL_ID_RETH_WETH,
            request: IVault.JoinPoolRequest({
                assets: assets,
                maxAmountsIn: maxAmountsIn,
                // EXACT_TOKENS_IN_FOR_BPT_OUT, amounts, min BPT
                userData: abi.encode(
                    IVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                    maxAmountsIn,
                    uint256(1)
                ),
                fromInternalBalance: false
            })
        });

        uint256 rethBal = reth.balanceOf(address(this));
        if (rethBal > 0) {
            reth.transfer(msg.sender, rethBal);
        }

        shares = rewardPool.balanceOf(address(this));
    }

    /// @notice Withdraw liquidity and claim rewards from the Aura protocol
    /// @param shares The number of shares to withdraw
    /// @param minRethAmountOut The minimum amount of RETH to receive from the withdrawal
    /// @dev This function withdraws liquidity, unwraps the rewards, and performs a Balancer exit.
    function exit(uint256 shares, uint256 minRethAmountOut) external auth {
        // Withdraw, unwrap and claim rewards
        require(rewardPool.withdrawAndUnwrap(shares, true), "withdraw failed");

        uint256 bptBal = IERC20(bpt).balanceOf(address(this));

        // Tokens must be ordered numerically by token address
        address[] memory assets = new address[](2);
        assets[0] = RETH;
        assets[1] = WETH;

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = minRethAmountOut;
        minAmountsOut[1] = 0;

        vault.exitPool({
            poolId: BALANCER_POOL_ID_RETH_WETH,
            sender: address(this),
            recipient: msg.sender,
            request: IVault.ExitPoolRequest({
                assets: assets,
                minAmountsOut: minAmountsOut,
                // EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, BPT amount, index of token to withdraw
                userData: abi.encode(
                    IVault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, bptBal, uint256(0)
                ),
                toInternalBalance: false
            })
        });
    }

    /// @notice Claim rewards from the Aura reward pool
    /// @dev This function triggers the reward claim from the reward pool on behalf of the contract's owner.
    function getReward() external auth {
        rewardPool.getReward();
    }

    /// @notice Transfer a specific token to a destination address
    /// @param token The address of the ERC20 token to transfer
    /// @param dst The destination address to send the token to
    /// @dev This function transfers all of the specified token from the contract's balance to the given destination.
    function transfer(address token, address dst) external auth {
        IERC20(token).transfer(dst, IERC20(token).balanceOf(address(this)));
    }
}

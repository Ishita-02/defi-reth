// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "../interfaces/IERC20.sol";
import {Pay} from "../aave/Pay.sol";
import {Token} from "../aave/Token.sol";
import {AaveHelper} from "../aave/AaveHelper.sol";
import {SwapHelper} from "../aave/SwapHelper.sol";

// Requirements
// - Delegatecall into this contract from Proxy
// - One Proxy contract per open position (coin / collateral pair)

/// @title FlashLev
/// @notice This contract allows for leveraged positions in Aave,
//          enabling users to open and close positions with flash loans.
/// @dev The contract interacts with Aave's flash loan, swap, and collateral management mechanisms.
contract FlashLev is Pay, Token, AaveHelper, SwapHelper {
    /*
    Definitions
    -----------
    HF = health factor
    LTV = ratio of loan to value of collateral

    Steps to open a position
    ------------------------
    1. Flash loan stable coin
    2. Swap stable coin to collateral <--- makes HF < target HF
    3. Supply swapped collateral + base collateral
    4. Borrow stable coin (flash loan amount + fee)
    5. Repay flash loan

    Steps to close a position
    -------------------------
    1. Flash loan stable coin
    2. Repay stable coin debt (open step 3)
    3. Withdraw collateral (open step 2)
    4. Swap collateral to stable coin
    5. Repay flash loan

    Math - find flash loan amount
    ------------------------
    total_borrow_usd / total_col_usd <= LTV

    total_borrow_usd = flash_loan_usd
                     = base_col_usd * k

    Assume swap_col_usd = flash_loan_usd (no slippage or fee on swap)

    total_col_usd = swap_col_usd + base_col_usd
                  = flash_loan_usd + base_col_usd
                  = base_col_usd * (k + 1)


    base_col_usd * k / (base_col_usd * (k + 1)) <= LTV
    k / (k + 1) <= LTV

    k <= LTV * (k + 1)
    k * (1 - LTV) <= LTV
    k <= LTV / (1 - LTV)

    flash_loan_usd = base_col_usd * k <= base_col_usd * LTV / (1 - LTV)
    */

    /// @notice Get the maximum flash loan amount for a given collateral type and base collateral amount
    /// @param collateral Address of the collateral asset
    /// @param baseColAmount The amount of collateral to use for the loan
    /// @return max The maximum flash loan amount (in USD with 18 decimals) that can be borrowed
    /// @return price The price of the collateral asset in USD (8 decimals)
    /// @return ltv The loan-to-value ratio for the collateral (4 decimals)
    /// @return maxLev The maximum leverage factor allowed for the collateral (4 decimals)
    /// @dev This function calculates the maximum loan amount and related values
    //       based on the collateral's price and LTV.
    function getMaxFlashLoanAmountUsd(address collateral, uint256 baseColAmount)
        external
        view
        returns (uint256 max, uint256 price, uint256 ltv, uint256 maxLev)
    {
        // Write your code here
        price = oracle.getAssetPrice(collateral);
        uint256 decimals;
        (decimals, ltv,,,,,,,,) = dataProvider.getReserveConfigurationData(collateral);
        maxLev = ltv * 1e4 / (1e4 - ltv);
        max = baseColAmount * 10 ** (18 - decimals) * ltv * price / (1e4 - ltv);
    }

    /// @notice Parameters for the swap process
    /// @param amountOutMin Minimum amount of output token to receive
    /// @param data Additional swap data
    struct SwapParams {
        uint256 amountOutMin;
        bytes data;
    }

    /// @notice Data structure for flash loan operations
    /// @param coin Address of the coin being borrowed
    /// @param collateral Address of the collateral asset
    /// @param open Boolean indicating if the position is being opened or closed
    /// @param caller The address of the user calling the operation
    /// @param colAmount The amount of collateral supplied by caller for opening a position.
    //                   For closing, this is the amount of collateral to keep.
    /// @param swap Swap parameters for collateral to coin swap
    struct FlashLoanData {
        address coin;
        address collateral;
        bool open;
        address caller;
        uint256 colAmount;
        SwapParams swap;
    }

    /// @notice Parameters for opening a leveraged position
    /// @param coin Address of the coin being borrowed
    /// @param collateral Address of the collateral asset
    /// @param colAmount The amount of collateral to deposit
    /// @param coinAmount The amount of coin to borrow via the flash loan
    /// @param swap Swap parameters for collateral to coin swap
    /// @param minHealthFactor The minimum health factor required for the position
    struct OpenParams {
        address coin;
        address collateral;
        uint256 colAmount;
        uint256 coinAmount;
        SwapParams swap;
        uint256 minHealthFactor;
    }

    /// @notice Parameters for closing a leveraged position
    /// @param coin Address of the coin being borrowed
    /// @param collateral Address of the collateral asset
    /// @param colAmount The amount of collateral to keep after closing the position
    /// @param swap Swap parameters for coin to collateral swap
    struct CloseParams {
        address coin;
        address collateral;
        uint256 colAmount;
        SwapParams swap;
    }

    /// @notice Open a leveraged position using a flash loan
    /// @param params Parameters for opening the position including collateral and coin amounts,
    //                and minimum health factor
    function open(OpenParams calldata params) external {
        // Write your code here
        IERC20(params.collateral).transferFrom(msg.sender, address(this), params.colAmount);
        bytes memory data = abi.encode(
            FlashLoanData({
                coin: params.coin,
                collateral: params.collateral,
                open: true,
                caller: msg.sender,
                colAmount: params.colAmount,
                swap: params.swap
        }));
        flashLoan(params.coin, params.coinAmount, data);
        uint256 healthFactor = getHealthFactor(address(this));
        assert(healthFactor >= params.minHealthFactor);
    }

    /// @notice Close a leveraged position by repaying the borrowed coin
    /// @param params Parameters for closing the position, including the amount of collateral to keep
    function close(CloseParams calldata params) external {
        // Write your code here
        uint256 totalDebt = getDebt(address(this), params.coin);
        bytes memory data = abi.encode(
            FlashLoanData({
                coin: params.coin,
                collateral: params.collateral,
                open: false,
                caller: msg.sender,
                colAmount: params.colAmount,
                swap: params.swap
        }));
        flashLoan(params.coin, totalDebt, data);
    }

    /// @notice Callback function for handling flash loan operations
    /// @param token Address of the token used in the flash loan
    /// @param amount The amount of the token borrowed
    /// @param fee The fee for the flash loan
    /// @param params Parameters for the flash loan operation. Decode it into FlashLoanData.
    /// @dev This function is executed after the flash loan is issued.
    //       It handles the logic for opening or closing positions.
    function _flashLoanCallback(
        address token,
        uint256 amount,
        uint256 fee,
        bytes memory params
    ) internal override {
        // Write your code here
        FlashLoanData memory flashLoanData = abi.decode(params, (FlashLoanData));

        if (flashLoanData.open) {
                uint256 colAmountOut = swap(flashLoanData.coin, flashLoanData.collateral, amount, flashLoanData.swap.amountOutMin, flashLoanData.swap.data);
            IERC20(flashLoanData.collateral).approve(address(pool), flashLoanData.colAmount + colAmountOut);
            supply(flashLoanData.collateral, flashLoanData.colAmount + colAmountOut);
            borrow(flashLoanData.coin, amount + fee);
            IERC20(flashLoanData.coin).approve(address(pool), amount + fee);
        } else {
            IERC20(flashLoanData.coin).approve(address(pool), amount + fee);
            repay(flashLoanData.coin, amount);
            uint256 colWithdrawn = withdraw(flashLoanData.collateral, type(uint256).max);
            IERC20(flashLoanData.collateral).transfer(flashLoanData.caller, flashLoanData.colAmount);
            uint256 swappedAmount = swap(flashLoanData.collateral, flashLoanData.coin, colWithdrawn - flashLoanData.colAmount, flashLoanData.swap.amountOutMin, flashLoanData.swap.data);

            if (swappedAmount >= amount + fee) {
                IERC20(flashLoanData.coin).transfer(flashLoanData.caller, swappedAmount - fee - amount);
            } else {
                IERC20(flashLoanData.coin).transferFrom(msg.sender, address(this), amount + fee - swappedAmount);
            }
        }
       
    }

}

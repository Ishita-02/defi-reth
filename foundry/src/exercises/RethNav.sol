// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRETH} from "../interfaces/rocket-pool/IRETH.sol";
import {IAggregatorV3} from "../interfaces/chainlink/IAggregatorV3.sol";
import {RETH, CHAINLINK_RETH_ETH} from "../Constants.sol";

/// @title RethNav
/// @notice Provides the Net Asset Value (NAV) and exchange rate of rETH using Rocket Pool and Chainlink.
/// @dev Interacts with Rocket Pool rETH contract and a Chainlink price feed to fetch exchange rates.
contract RethNav {
    IRETH private constant reth = IRETH(RETH);
    IAggregatorV3 private constant agg = IAggregatorV3(CHAINLINK_RETH_ETH);

    /// @notice Fetches the current exchange rate of rETH from Rocket Pool contract.
    /// @return The exchange rate of 1 rETH into ETH in wei (18 decimals).
    function getExchangeRate() external view returns (uint256) {
        // Write your code here
        return reth.getExchangeRate();
    }

    /// @notice Fetches the current exchange rate of rETH from the Chainlink price feed.
    /// @return The exchange rate of rETH in wei (18 decimals).
    /// @dev Ensures the price data is not stale and the rate is non-negative.
    function getExchangeRateFromChainlink() external view returns (uint256) {
        (
            , // uint80 roundId,
            int256 rate,
            , // uint256 startedAt,
            uint256 updatedAt,
            // uint80 answeredInRound
        ) = agg.latestRoundData();

        require(updatedAt >= block.timestamp - 24 * 3600, "stale price");
        require(rate >= 0, "rate < 0");

        return uint256(rate);
    }
}

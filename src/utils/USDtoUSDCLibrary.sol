// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library USDtoUSDCLibrary {
    function convert(
        uint256 usdValue,
        uint256 usdcPriceInUsd,
        uint256 usdcDecimals,
        uint256 feedDecimals // USDC/USD rate/feed decimals
    ) external pure returns (uint256) {
        uint256 conversionResult = Math.mulDiv(
            (usdValue * 10 ** usdcDecimals),
            10 ** feedDecimals,
            usdcPriceInUsd
        );

        return conversionResult;
    }
}

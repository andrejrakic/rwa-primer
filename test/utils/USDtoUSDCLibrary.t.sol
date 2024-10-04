// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {USDtoUSDCLibrary} from "../../src/utils/USDtoUSDCLibrary.sol";

contract USDtoUSDCLibraryTest is Test {
    function test_conversion_1_usd_with_1_usdc_equals_1_usd_rate() public pure {
        uint256 usdValue = 1;
        uint256 usdcPriceInUsd = 100000000; // 1 USDC equals 1.00000000 USD // 8 digits
        uint256 usdcDecimals = 6;
        uint256 feedDecimals = 8;
        uint256 conversionResult = USDtoUSDCLibrary.convert(
            usdValue,
            usdcPriceInUsd,
            usdcDecimals,
            feedDecimals
        );

        assertEq(conversionResult, 1000000); // 1.000000
    }

    function test_conversion_1_usd_with_1_usdc_less_than_1_usd_rate()
        public
        pure
    {
        uint256 usdValue = 1;
        uint256 usdcPriceInUsd = 99997689; // 1 USDC equals 0.99997689 USD // 8 digits
        uint256 usdcDecimals = 6;
        uint256 feedDecimals = 8;
        uint256 conversionResult = USDtoUSDCLibrary.convert(
            usdValue,
            usdcPriceInUsd,
            usdcDecimals,
            feedDecimals
        );

        assertEq(conversionResult, 1000023); // 1.000023
    }

    function test_conversion_100_usd_with_1_usdc_less_than_1_usd_rate()
        public
        pure
    {
        uint256 usdValue = 100;
        uint256 usdcPriceInUsd = 99997689; // 1 USDC equals 0.99997689 USD // 8 digits
        uint256 usdcDecimals = 6;
        uint256 feedDecimals = 8;
        uint256 conversionResult = USDtoUSDCLibrary.convert(
            usdValue,
            usdcPriceInUsd,
            usdcDecimals,
            feedDecimals
        );

        assertEq(conversionResult, 100002311); // 100.002311
    }

    function test_conversion_1_usd_with_1_usdc_greater_than_1_usd_rate()
        public
        pure
    {
        uint256 usdValue = 1;
        uint256 usdcPriceInUsd = 100002311; // 1 USDC equals 1.00002311 USD // 8 digits
        uint256 usdcDecimals = 6;
        uint256 feedDecimals = 8;
        uint256 conversionResult = USDtoUSDCLibrary.convert(
            usdValue,
            usdcPriceInUsd,
            usdcDecimals,
            feedDecimals
        );

        assertEq(conversionResult, 999976); // 0.999976, note that 1 - 0.999976 = 0.000024 about 0.00002311
    }

    function test_conversion_100_usd_with_1_usdc_greater_than_1_usd_rate()
        public
        pure
    {
        uint256 usdValue = 100;
        uint256 usdcPriceInUsd = 100002311; // 1 USDC equals 1.00002311 USD // 8 digits
        uint256 usdcDecimals = 6;
        uint256 feedDecimals = 8;
        uint256 conversionResult = USDtoUSDCLibrary.convert(
            usdValue,
            usdcPriceInUsd,
            usdcDecimals,
            feedDecimals
        );

        assertEq(conversionResult, 99997689); // 99.997689
    }
}

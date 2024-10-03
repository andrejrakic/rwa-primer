// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RealEstateToken} from "../RealEstateToken.sol";
import {IERC1155Receiver, IERC165} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract RwaLending is IERC1155Receiver, OwnerIsCreator, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct LoanDetails {
        uint256 erc1155AmountSupplied;
        uint256 usdcAmountLoaned;
        uint256 usdcLiquidationThreshold;
    }

    RealEstateToken internal immutable i_realEstateToken;
    address internal immutable i_usdc;
    AggregatorV3Interface internal s_usdcUsdAggregator;
    uint32 internal s_usdcUsdFeedHeartbeat;

    uint256 internal immutable i_weightListPrice;
    uint256 internal immutable i_weightOriginalListPrice;
    uint256 internal immutable i_weightTaxAssessedValue;
    uint256 internal immutable i_ltvInitialThreshold;
    uint256 internal immutable i_ltvLiquidationThreshold;

    mapping(uint256 tokenId => mapping(address borrower => LoanDetails)) internal s_activeLoans;

    event Borrow(
        uint256 indexed tokenId, uint256 amount, uint256 indexed loanAmount, uint256 indexed liquidationThreshold
    );
    event BorrowRepayed(uint256 indexed tokenId, uint256 indexed amount);
    event Liquidated(uint256 indexed tokenId);

    error AlreadyBorrowed(address borrower, uint256 tokenId);
    error OnlyRealEstateTokenSupported();
    error InvalidValuation();
    error SlippageToleranceExceeded();
    error PriceFeedDdosed();
    error InvalidRoundId();
    error StalePriceFeed();
    error NothingToRepay();

    constructor(
        address realEstateTokenAddress,
        address usdc,
        address usdcUsdAggregatorAddress,
        uint32 usdcUsdFeedHeartbeat
    ) {
        i_realEstateToken = RealEstateToken(realEstateTokenAddress);
        i_usdc = usdc;
        s_usdcUsdAggregator = AggregatorV3Interface(usdcUsdAggregatorAddress);
        s_usdcUsdFeedHeartbeat = usdcUsdFeedHeartbeat;

        i_weightListPrice = 50;
        i_weightOriginalListPrice = 30;
        i_weightTaxAssessedValue = 20;

        i_ltvInitialThreshold = 60;
        i_ltvLiquidationThreshold = 75;
    }

    function borrow(
        uint256 tokenId,
        uint256 amount,
        bytes memory data,
        uint256 minLoanAmount,
        uint256 maxLiquidationThreshold
    ) external nonReentrant {
        if (s_activeLoans[tokenId][msg.sender].usdcAmountLoaned != 0) revert AlreadyBorrowed(msg.sender, tokenId);

        uint256 normalizedValuation = getValuationInUsdc(tokenId) * amount / i_realEstateToken.totalSupply(tokenId);

        if (normalizedValuation == 0) revert InvalidValuation();

        uint256 loanAmount = (normalizedValuation * i_ltvInitialThreshold) / 100;
        if (loanAmount < minLoanAmount) revert SlippageToleranceExceeded();

        uint256 liquidationThreshold = (normalizedValuation * i_ltvLiquidationThreshold) / 100;
        if (liquidationThreshold > maxLiquidationThreshold) {
            revert SlippageToleranceExceeded();
        }

        i_realEstateToken.safeTransferFrom(msg.sender, address(this), tokenId, amount, data);

        s_activeLoans[tokenId][msg.sender] = LoanDetails({
            erc1155AmountSupplied: amount,
            usdcAmountLoaned: loanAmount,
            usdcLiquidationThreshold: liquidationThreshold
        });

        IERC20(i_usdc).safeTransfer(msg.sender, loanAmount);

        emit Borrow(tokenId, amount, loanAmount, liquidationThreshold);
    }

    function repay(uint256 tokenId) external nonReentrant {
        LoanDetails memory loanDetails = s_activeLoans[tokenId][msg.sender];
        if (loanDetails.usdcAmountLoaned == 0) revert NothingToRepay();

        delete s_activeLoans[tokenId][msg.sender];

        IERC20(i_usdc).safeTransferFrom(msg.sender, address(this), loanDetails.usdcAmountLoaned);

        i_realEstateToken.safeTransferFrom(address(this), msg.sender, tokenId, loanDetails.erc1155AmountSupplied, "");

        emit BorrowRepayed(tokenId, loanDetails.erc1155AmountSupplied);
    }

    function liquidate(uint256 tokenId, address borrower) external {
        LoanDetails memory loanDetails = s_activeLoans[tokenId][borrower];

        uint256 normalizedValuation =
            getValuationInUsdc(tokenId) * loanDetails.erc1155AmountSupplied / i_realEstateToken.totalSupply(tokenId);
        if (normalizedValuation == 0) revert InvalidValuation();

        uint256 liquidationThreshold = (normalizedValuation * i_ltvLiquidationThreshold) / 100;
        if (liquidationThreshold < loanDetails.usdcLiquidationThreshold) {
            delete s_activeLoans[tokenId][borrower];
        }
    }

    function getUsdcPriceInUsd() public view returns (uint256) {
        uint80 _roundId;
        int256 _price;
        uint256 _updatedAt;
        try s_usdcUsdAggregator.latestRoundData() returns (
            uint80 roundId,
            int256 price,
            uint256,
            /* startedAt */
            uint256 updatedAt,
            uint80 /* answeredInRound */
        ) {
            _roundId = roundId;
            _price = price;
            _updatedAt = updatedAt;
        } catch {
            revert PriceFeedDdosed();
        }

        if (_roundId == 0) revert InvalidRoundId();

        if (_updatedAt < block.timestamp - s_usdcUsdFeedHeartbeat) {
            revert StalePriceFeed();
        }

        return uint256(_price);
    }

    function getValuationInUsdc(uint256 tokenId) public view returns (uint256) {
        RealEstateToken.PriceDetails memory priceDetails = i_realEstateToken.getPriceDetails(tokenId);

        uint256 valuation = (
            i_weightListPrice * priceDetails.listPrice + i_weightOriginalListPrice * priceDetails.originalListPrice
                + i_weightTaxAssessedValue * priceDetails.taxAssessedValue
        ) / (i_weightListPrice + i_weightOriginalListPrice + i_weightTaxAssessedValue);

        uint256 usdcPriceInUsd = getUsdcPriceInUsd();

        uint256 feedDecimals = s_usdcUsdAggregator.decimals();
        uint256 usdcDecimals = 6; // USDC uses 6 decimals

        uint256 normalizedValuation = Math.mulDiv((valuation * usdcPriceInUsd), 10 ** usdcDecimals, 10 ** feedDecimals); // Adjust the valuation from USD (Chainlink 1e8) to USDC (1e6)

        return normalizedValuation;
    }

    function setUsdcUsdPriceFeedDetails(address usdcUsdAggregatorAddress, uint32 usdcUsdFeedHeartbeat)
        external
        onlyOwner
    {
        s_usdcUsdAggregator = AggregatorV3Interface(usdcUsdAggregatorAddress);
        s_usdcUsdFeedHeartbeat = usdcUsdFeedHeartbeat;
    }

    function onERC1155Received(
        address, /*operator*/
        address, /*from*/
        uint256, /*id*/
        uint256, /*value*/
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        if (msg.sender != address(i_realEstateToken)) {
            revert OnlyRealEstateTokenSupported();
        }

        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address, /*operator*/
        address, /*from*/
        uint256[] calldata, /*ids*/
        uint256[] calldata, /*values*/
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        if (msg.sender != address(i_realEstateToken)) {
            revert OnlyRealEstateTokenSupported();
        }

        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

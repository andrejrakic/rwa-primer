// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver, IERC165} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract EnglishAuction is IERC1155Receiver, ReentrancyGuard {
    error EnglishAuction_OnlySellerCanCall();
    error EnglishAuction_AuctionAlreadyStarted();
    error OnlyRealEstateTokenSupported();
    error EnglishAuction_NoAuctionsInProgress();
    error EnglishAuction_AuctionEnded();
    error EnglishAuction_BidNotHighEnough();
    error EnglishAuction_CannotWithdrawHighestBid();
    error EnglishAuction_TooEarlyToEnd();
    error FailedToWithdrawBid(address bidder, uint256 amount);
    error NothingToWithdraw();
    error FailedToSendEth(address recipient, uint256 amount);

    address internal immutable i_seller;
    address internal immutable i_fractionalizedRealEstateToken;

    bool internal s_started;
    uint48 internal s_endTimestamp;
    address internal s_highestBidder;
    uint256 internal s_highestBid;
    uint256 internal s_tokenIdOnAuction;
    uint256 internal s_fractionalizedAmountOnAuction;

    mapping(address bidder => uint256 totalBiddedEth) internal s_bids;

    event AuctionStarted(uint256 indexed tokenId, uint256 indexed amount, uint48 indexed endTimestamp);
    event Bid(address indexed bidder, uint256 indexed amount);
    event AuctionEnded(uint256 indexed tokenId, uint256 amount, address indexed winner, uint256 indexed winningBid);

    constructor(address fractionalizedRealEstateTokenAddress) {
        i_seller = msg.sender;
        i_fractionalizedRealEstateToken = fractionalizedRealEstateTokenAddress;
    }

    function startAuction(uint256 tokenId, uint256 amount, bytes calldata data, uint256 startingBid)
        external
        nonReentrant
    {
        if (s_started) revert EnglishAuction_AuctionAlreadyStarted();
        if (msg.sender != i_seller) revert EnglishAuction_OnlySellerCanCall();

        IERC1155(i_fractionalizedRealEstateToken).safeTransferFrom(i_seller, address(this), tokenId, amount, data);

        s_started = true;
        s_endTimestamp = SafeCast.toUint48(block.timestamp + 7 days);
        s_tokenIdOnAuction = tokenId;
        s_fractionalizedAmountOnAuction = amount;
        s_highestBidder = msg.sender;
        s_highestBid = startingBid;

        emit AuctionStarted(tokenId, amount, s_endTimestamp);
    }

    function getTokenIdOnAuction() external view returns (uint256) {
        return s_tokenIdOnAuction;
    }

    function bid() external payable nonReentrant {
        if (!s_started) revert EnglishAuction_NoAuctionsInProgress();
        if (block.timestamp >= s_endTimestamp) revert EnglishAuction_AuctionEnded();
        if (msg.value <= s_highestBid) revert EnglishAuction_BidNotHighEnough();

        s_highestBidder = msg.sender;
        s_highestBid = msg.value;
        s_bids[msg.sender] += msg.value;

        emit Bid(msg.sender, msg.value);
    }

    function withdrawBid() external nonReentrant {
        if (msg.sender == s_highestBidder) revert EnglishAuction_CannotWithdrawHighestBid();

        uint256 amount = s_bids[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        delete s_bids[msg.sender];

        (bool sent,) = msg.sender.call{value: amount}("");

        if (!sent) revert FailedToWithdrawBid(msg.sender, amount);
    }

    function endAuction() external nonReentrant {
        if (!s_started) revert EnglishAuction_NoAuctionsInProgress();
        if (block.timestamp < s_endTimestamp) revert EnglishAuction_TooEarlyToEnd();

        s_started = false;

        IERC1155(i_fractionalizedRealEstateToken).safeTransferFrom(
            address(this), s_highestBidder, s_tokenIdOnAuction, s_fractionalizedAmountOnAuction, ""
        );

        (bool sent,) = i_seller.call{value: s_highestBid}("");
        if (!sent) revert FailedToSendEth(i_seller, s_highestBid);

        emit AuctionEnded(s_tokenIdOnAuction, s_fractionalizedAmountOnAuction, s_highestBidder, s_highestBid);
    }

    function onERC1155Received(
        address, /*operator*/
        address, /*from*/
        uint256, /*id*/
        uint256, /*value*/
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        if (msg.sender != address(i_fractionalizedRealEstateToken)) {
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
        if (msg.sender != address(i_fractionalizedRealEstateToken)) {
            revert OnlyRealEstateTokenSupported();
        }

        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

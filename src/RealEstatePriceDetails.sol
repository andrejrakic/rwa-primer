// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {FunctionsSource} from "./FunctionsSource.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract RealEstatePriceDetails is FunctionsClient, FunctionsSource, OwnerIsCreator {
    using FunctionsRequest for FunctionsRequest.Request;

    struct PriceDetails {
        uint80 listPrice;
        uint80 originalListPrice;
        uint80 taxAssessedValue;
    }

    address internal s_automationForwarderAddress;

    mapping(uint256 tokenId => PriceDetails) internal s_priceDetails;

    error OnlyAutomationForwarderOrOwnerCanCall();

    modifier onlyAutomationForwarderOrOwner() {
        if (msg.sender != s_automationForwarderAddress && msg.sender != owner()) {
            revert OnlyAutomationForwarderOrOwnerCanCall();
        }
        _;
    }

    constructor(address functionsRouterAddress) FunctionsClient(functionsRouterAddress) {}

    function setAutomationForwarder(address automationForwarderAddress) external onlyOwner {
        s_automationForwarderAddress = automationForwarderAddress;
    }

    function updatePriceDetails(string memory tokenId, uint64 subscriptionId, uint32 gasLimit, bytes32 donID)
        external
        onlyAutomationForwarderOrOwner
        returns (bytes32 requestId)
    {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(this.getPrices());

        string[] memory args = new string[](1);
        args[0] = tokenId;

        req.setArgs(args);

        requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);
    }

    function getPriceDetails(uint256 tokenId) external view returns (PriceDetails memory) {
        return s_priceDetails[tokenId];
    }

    function fulfillRequest(bytes32, /*requestId*/ bytes memory response, bytes memory err) internal override {
        if (err.length != 0) {
            revert(string(err));
        }

        (uint256 tokenId, uint256 listPrice, uint256 originalListPrice, uint256 taxAssessedValue) =
            abi.decode(response, (uint256, uint256, uint256, uint256));

        s_priceDetails[tokenId] = PriceDetails({
            listPrice: uint80(listPrice),
            originalListPrice: uint80(originalListPrice),
            taxAssessedValue: uint80(taxAssessedValue)
        });
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RealEstateToken} from "./RealEstateToken.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {FunctionsSource} from "./FunctionsSource.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract Issuer is FunctionsClient, FunctionsSource, OwnerIsCreator {
    using FunctionsRequest for FunctionsRequest.Request;

    error LatestIssueInProgress();

    struct FractionalizedNft {
        address to;
        uint256 amount;
    }

    RealEstateToken internal immutable i_realEstateToken;

    bytes32 internal s_lastRequestId;
    uint256 private s_nextTokenId;

    mapping(bytes32 requestId => FractionalizedNft) internal s_issuesInProgress;

    constructor(address realEstateToken, address functionsRouterAddress) FunctionsClient(functionsRouterAddress) {
        i_realEstateToken = RealEstateToken(realEstateToken);
    }

    function issue(address to, uint256 amount, uint64 subscriptionId, uint32 gasLimit, bytes32 donID)
        external
        onlyOwner
        returns (bytes32 requestId)
    {
        if (s_lastRequestId != bytes32(0)) revert LatestIssueInProgress();

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(this.getNftMetadata());
        requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);

        s_issuesInProgress[requestId] = FractionalizedNft(to, amount);

        s_lastRequestId = requestId;
    }

    function cancelPendingRequest() external onlyOwner {
        s_lastRequestId = bytes32(0);
    }

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        if (err.length != 0) {
            revert(string(err));
        }

        if (s_lastRequestId == requestId) {
            string memory tokenURI = string(response);

            uint256 tokenId = s_nextTokenId++;
            FractionalizedNft memory fractionalizedNft = s_issuesInProgress[requestId];

            i_realEstateToken.mint(fractionalizedNft.to, tokenId, fractionalizedNft.amount, "", tokenURI);

            s_lastRequestId = bytes32(0);
        }
    }
}

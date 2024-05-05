// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {FunctionsSource} from "./FunctionsSource.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract xRealEstateNFT is
    ERC721,
    ERC721URIStorage,
    ERC721Burnable,
    FunctionsClient,
    IAny2EVMMessageReceiver,
    ReentrancyGuard,
    OwnerIsCreator
{
    using FunctionsRequest for FunctionsRequest.Request;
    using SafeERC20 for IERC20;

    enum PayFeesIn {
        Native,
        LINK
    }

    error InvalidRouter(address router);
    error OnlyOnArbitrumSepolia();
    error NotEnoughBalanceForFees(uint256 currentBalance, uint256 calculatedFees);
    error NothingToWithdraw();
    error FailedToWithdrawEth(address owner, address target, uint256 value);
    error ChainNotEnabled(uint64 chainSelector);
    error SenderNotEnabled(address sender);
    error OperationNotAllowedOnCurrentChain(uint64 chainSelector);
    error LatestIssueInProgress();
    error OnlyAutomationForwarderCanCall();

    struct XNftDetails {
        address xNftAddress;
        bytes ccipExtraArgsBytes;
    }

    struct PriceDetails {
        uint80 listPrice;
        uint80 originalListPrice;
        uint80 taxAssessedValue;
    }

    uint256 constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;

    FunctionsSource internal immutable i_functionsSource;
    IRouterClient internal immutable i_ccipRouter;
    LinkTokenInterface internal immutable i_linkToken;
    uint64 private immutable i_currentChainSelector;

    bytes32 internal s_lastRequestId;
    address internal s_automationForwarderAddress;

    uint256 private _nextTokenId;

    mapping(uint64 destChainSelector => XNftDetails xNftDetailsPerChain) public s_chains;
    mapping(bytes32 requestId => address to) internal s_issueTo;
    mapping(uint256 tokenId => PriceDetails) internal s_priceDetails;

    event ChainEnabled(uint64 chainSelector, address xNftAddress, bytes ccipExtraArgs);
    event ChainDisabled(uint64 chainSelector);
    event CrossChainSent(
        address from, address to, uint256 tokenId, uint64 sourceChainSelector, uint64 destinationChainSelector
    );
    event CrossChainReceived(
        address from, address to, uint256 tokenId, uint64 sourceChainSelector, uint64 destinationChainSelector
    );

    modifier onlyRouter() {
        if (msg.sender != address(i_ccipRouter)) {
            revert InvalidRouter(msg.sender);
        }
        _;
    }

    modifier onlyAutomationForwarder() {
        if (msg.sender != s_automationForwarderAddress) {
            revert OnlyAutomationForwarderCanCall();
        }
        _;
    }

    modifier onlyOnArbitrumSepolia() {
        if (block.chainid != ARBITRUM_SEPOLIA_CHAIN_ID) {
            revert OnlyOnArbitrumSepolia();
        }
        _;
    }

    modifier onlyEnabledChain(uint64 _chainSelector) {
        if (s_chains[_chainSelector].xNftAddress == address(0)) {
            revert ChainNotEnabled(_chainSelector);
        }
        _;
    }

    modifier onlyEnabledSender(uint64 _chainSelector, address _sender) {
        if (s_chains[_chainSelector].xNftAddress != _sender) {
            revert SenderNotEnabled(_sender);
        }
        _;
    }

    modifier onlyOtherChains(uint64 _chainSelector) {
        if (_chainSelector == i_currentChainSelector) {
            revert OperationNotAllowedOnCurrentChain(_chainSelector);
        }
        _;
    }

    constructor(
        address functionsRouterAddress,
        address ccipRouterAddress,
        address linkTokenAddress,
        uint64 currentChainSelector
    ) ERC721("Cross Chain Tokenized Real Estate", "xRealEstateNFT") FunctionsClient(functionsRouterAddress) {
        if (ccipRouterAddress == address(0)) revert InvalidRouter(address(0));
        i_functionsSource = new FunctionsSource();
        i_ccipRouter = IRouterClient(ccipRouterAddress);
        i_linkToken = LinkTokenInterface(linkTokenAddress);
        i_currentChainSelector = currentChainSelector;
    }

    function issue(address to, uint64 subscriptionId, uint32 gasLimit, bytes32 donID)
        external
        onlyOwner
        onlyOnArbitrumSepolia
        returns (bytes32 requestId)
    {
        if (s_lastRequestId != bytes32(0)) revert LatestIssueInProgress();

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(i_functionsSource.getNftMetadata());
        requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);

        s_issueTo[requestId] = to;
    }

    function enableChain(uint64 chainSelector, address xNftAddress, bytes memory ccipExtraArgs)
        external
        onlyOwner
        onlyOtherChains(chainSelector)
    {
        s_chains[chainSelector] = XNftDetails({xNftAddress: xNftAddress, ccipExtraArgsBytes: ccipExtraArgs});

        emit ChainEnabled(chainSelector, xNftAddress, ccipExtraArgs);
    }

    function disableChain(uint64 chainSelector) external onlyOwner onlyOtherChains(chainSelector) {
        delete s_chains[chainSelector];

        emit ChainDisabled(chainSelector);
    }

    function crossChainTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        uint64 destinationChainSelector,
        PayFeesIn payFeesIn
    ) external nonReentrant onlyEnabledChain(destinationChainSelector) returns (bytes32 messageId) {
        string memory tokenUri = tokenURI(tokenId);
        _burn(tokenId);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(s_chains[destinationChainSelector].xNftAddress),
            data: abi.encode(from, to, tokenId, tokenUri),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: s_chains[destinationChainSelector].ccipExtraArgsBytes,
            feeToken: payFeesIn == PayFeesIn.LINK ? address(i_linkToken) : address(0)
        });

        // Get the fee required to send the CCIP message
        uint256 fees = i_ccipRouter.getFee(destinationChainSelector, message);

        if (payFeesIn == PayFeesIn.LINK) {
            if (fees > i_linkToken.balanceOf(address(this))) {
                revert NotEnoughBalanceForFees(i_linkToken.balanceOf(address(this)), fees);
            }

            // Approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
            i_linkToken.approve(address(i_ccipRouter), fees);

            // Send the message through the router and store the returned message ID
            messageId = i_ccipRouter.ccipSend(destinationChainSelector, message);
        } else {
            if (fees > address(this).balance) {
                revert NotEnoughBalanceForFees(address(this).balance, fees);
            }

            // Send the message through the router and store the returned message ID
            messageId = i_ccipRouter.ccipSend{value: fees}(destinationChainSelector, message);
        }

        emit CrossChainSent(from, to, tokenId, i_currentChainSelector, destinationChainSelector);
    }

    /// @inheritdoc IAny2EVMMessageReceiver
    function ccipReceive(Client.Any2EVMMessage calldata message)
        external
        virtual
        override
        onlyRouter
        nonReentrant
        onlyEnabledChain(message.sourceChainSelector)
        onlyEnabledSender(message.sourceChainSelector, abi.decode(message.sender, (address)))
    {
        uint64 sourceChainSelector = message.sourceChainSelector;
        (address from, address to, uint256 tokenId, string memory tokenUri) =
            abi.decode(message.data, (address, address, uint256, string));

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenUri);

        emit CrossChainReceived(from, to, tokenId, sourceChainSelector, i_currentChainSelector);
    }

    function setAutomationForwarder(address automationForwarderAddress) external onlyOwner {
        s_automationForwarderAddress = automationForwarderAddress;
    }

    function updatePriceDetails(uint256 tokenId, uint64 subscriptionId, uint32 gasLimit, bytes32 donID)
        external
        onlyAutomationForwarder
        returns (bytes32 requestId)
    {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(i_functionsSource.getPrices());

        string[] memory args = new string[](1);
        args[0] = string(abi.encode(tokenId));

        requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);
    }

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        if (s_lastRequestId == requestId) {
            (string memory realEstateAddress, uint256 yearBuilt, uint256 lotSizeSquareFeet) =
                abi.decode(response, (string, uint256, uint256));

            uint256 tokenId = _nextTokenId++;

            string memory uri = Base64.encode(
                bytes(
                    string(
                        abi.encodePacked(
                            '{"name": "Cross Chain Tokenized Real Estate",'
                            '"description": "Cross Chain Tokenized Real Estate",',
                            '"image": "",' '"attributes": [',
                            '{"trait_type": "realEstateAddress",',
                            '"value": ',
                            realEstateAddress,
                            "}",
                            ',{"trait_type": "yearBuilt",',
                            '"value": ',
                            yearBuilt,
                            "}",
                            ',{"trait_type": "lotSizeSquareFeet",',
                            '"value": ',
                            lotSizeSquareFeet,
                            "}",
                            "]}"
                        )
                    )
                )
            );
            string memory finalTokenURI = string(abi.encodePacked("data:application/json;base64,", uri));

            _safeMint(s_issueTo[requestId], tokenId);
            _setTokenURI(tokenId, finalTokenURI);
        } else {
            (uint256 tokenId, uint256 listPrice, uint256 originalListPrice, uint256 taxAssessedValue) =
                abi.decode(response, (uint256, uint256, uint256, uint256));

            s_priceDetails[tokenId] = PriceDetails({
                listPrice: uint80(listPrice),
                originalListPrice: uint80(originalListPrice),
                taxAssessedValue: uint80(taxAssessedValue)
            });
        }
    }

    function withdraw(address _beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;

        if (amount == 0) revert NothingToWithdraw();

        (bool sent,) = _beneficiary.call{value: amount}("");

        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    function withdrawToken(address _beneficiary, address _token) public onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));

        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).safeTransfer(_beneficiary, amount);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function getPriceDetails(uint256 tokenId) external view returns (PriceDetails memory) {
        return s_priceDetails[tokenId];
    }

    function getCCIPRouter() public view returns (address) {
        return address(i_ccipRouter);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || super.supportsInterface(interfaceId);
    }
}

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

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract xRealEstateNFT is
    ERC721,
    ERC721URIStorage,
    ERC721Burnable,
    IAny2EVMMessageReceiver,
    ReentrancyGuard,
    OwnerIsCreator
{
    using SafeERC20 for IERC20;

    enum PayFeesIn {
        Native,
        LINK
    }

    error InvalidRouter(address router);
    error OnlyOnArbitrumSepolia();
    error NotEnoughBalanceForFees(
        uint256 currentBalance,
        uint256 calculatedFees
    );
    error NothingToWithdraw();
    error FailedToWithdrawEth(address owner, address target, uint256 value);
    error ChainNotEnabled(uint64 chainSelector);
    error SenderNotEnabled(address sender);
    error OperationNotAllowedOnCurrentChain(uint64 chainSelector);

    struct XNftDetails {
        address xNftAddress;
        bytes ccipExtraArgsBytes;
    }

    uint256 constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;

    string[] characters = [
        "https://ipfs.io/ipfs/QmTgqnhFBMkfT9s8PHKcdXBn1f5bG3Q5hmBaR4U6hoTvb1?filename=Chainlink_Elf.png",
        "https://ipfs.io/ipfs/QmZGQA92ri1jfzSu61JRaNQXYg1bLuM7p8YT83DzFA2KLH?filename=Chainlink_Knight.png",
        "https://ipfs.io/ipfs/QmW1toapYs7M29rzLXTENn3pbvwe8ioikX1PwzACzjfdHP?filename=Chainlink_Orc.png",
        "https://ipfs.io/ipfs/QmPMwQtFpEdKrUjpQJfoTeZS1aVSeuJT6Mof7uV29AcUpF?filename=Chainlink_Witch.png"
    ];

    IRouterClient internal immutable i_ccipRouter;
    LinkTokenInterface internal immutable i_linkToken;
    uint64 private immutable i_currentChainSelector;

    uint256 private _nextTokenId;

    mapping(uint64 destChainSelector => XNftDetails xNftDetailsPerChain)
        public s_chains;

    event ChainEnabled(
        uint64 chainSelector,
        address xNftAddress,
        bytes ccipExtraArgs
    );
    event ChainDisabled(uint64 chainSelector);
    event CrossChainSent(
        address from,
        address to,
        uint256 tokenId,
        uint64 sourceChainSelector,
        uint64 destinationChainSelector
    );
    event CrossChainReceived(
        address from,
        address to,
        uint256 tokenId,
        uint64 sourceChainSelector,
        uint64 destinationChainSelector
    );

    modifier onlyRouter() {
        if (msg.sender != address(i_ccipRouter))
            revert InvalidRouter(msg.sender);
        _;
    }

    modifier onlyOnArbitrumSepolia() {
        if (block.chainid != ARBITRUM_SEPOLIA_CHAIN_ID)
            revert OnlyOnArbitrumSepolia();
        _;
    }

    modifier onlyEnabledChain(uint64 _chainSelector) {
        if (s_chains[_chainSelector].xNftAddress == address(0))
            revert ChainNotEnabled(_chainSelector);
        _;
    }

    modifier onlyEnabledSender(uint64 _chainSelector, address _sender) {
        if (s_chains[_chainSelector].xNftAddress != _sender)
            revert SenderNotEnabled(_sender);
        _;
    }

    modifier onlyOtherChains(uint64 _chainSelector) {
        if (_chainSelector == i_currentChainSelector)
            revert OperationNotAllowedOnCurrentChain(_chainSelector);
        _;
    }

    constructor(
        address ccipRouterAddress,
        address linkTokenAddress,
        uint64 currentChainSelector
    ) ERC721("Cross Chain NFT", "XNFT") {
        if (ccipRouterAddress == address(0)) revert InvalidRouter(address(0));
        i_ccipRouter = IRouterClient(ccipRouterAddress);
        i_linkToken = LinkTokenInterface(linkTokenAddress);
        i_currentChainSelector = currentChainSelector;
    }

    function mint() external onlyOnArbitrumSepolia {
        uint256 tokenId = _nextTokenId++;
        string memory uri = characters[tokenId % characters.length];
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, uri);
    }

    function enableChain(
        uint64 chainSelector,
        address xNftAddress,
        bytes memory ccipExtraArgs
    ) external onlyOwner onlyOtherChains(chainSelector) {
        s_chains[chainSelector] = XNftDetails({
            xNftAddress: xNftAddress,
            ccipExtraArgsBytes: ccipExtraArgs
        });

        emit ChainEnabled(chainSelector, xNftAddress, ccipExtraArgs);
    }

    function disableChain(
        uint64 chainSelector
    ) external onlyOwner onlyOtherChains(chainSelector) {
        delete s_chains[chainSelector];

        emit ChainDisabled(chainSelector);
    }

    function crossChainTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        uint64 destinationChainSelector,
        PayFeesIn payFeesIn
    )
        external
        nonReentrant
        onlyEnabledChain(destinationChainSelector)
        returns (bytes32 messageId)
    {
        string memory tokenUri = tokenURI(tokenId);
        _burn(tokenId);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(
                s_chains[destinationChainSelector].xNftAddress
            ),
            data: abi.encode(from, to, tokenId, tokenUri),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: s_chains[destinationChainSelector].ccipExtraArgsBytes,
            feeToken: payFeesIn == PayFeesIn.LINK
                ? address(i_linkToken)
                : address(0)
        });

        // Get the fee required to send the CCIP message
        uint256 fees = i_ccipRouter.getFee(destinationChainSelector, message);

        if (payFeesIn == PayFeesIn.LINK) {
            if (fees > i_linkToken.balanceOf(address(this)))
                revert NotEnoughBalanceForFees(
                    i_linkToken.balanceOf(address(this)),
                    fees
                );

            // Approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
            i_linkToken.approve(address(i_ccipRouter), fees);

            // Send the message through the router and store the returned message ID
            messageId = i_ccipRouter.ccipSend(
                destinationChainSelector,
                message
            );
        } else {
            if (fees > address(this).balance)
                revert NotEnoughBalanceForFees(address(this).balance, fees);

            // Send the message through the router and store the returned message ID
            messageId = i_ccipRouter.ccipSend{value: fees}(
                destinationChainSelector,
                message
            );
        }

        emit CrossChainSent(
            from,
            to,
            tokenId,
            i_currentChainSelector,
            destinationChainSelector
        );
    }

    /// @inheritdoc IAny2EVMMessageReceiver
    function ccipReceive(
        Client.Any2EVMMessage calldata message
    )
        external
        virtual
        override
        onlyRouter
        nonReentrant
        onlyEnabledChain(message.sourceChainSelector)
        onlyEnabledSender(
            message.sourceChainSelector,
            abi.decode(message.sender, (address))
        )
    {
        uint64 sourceChainSelector = message.sourceChainSelector;
        (
            address from,
            address to,
            uint256 tokenId,
            string memory tokenUri
        ) = abi.decode(message.data, (address, address, uint256, string));

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenUri);

        emit CrossChainReceived(
            from,
            to,
            tokenId,
            sourceChainSelector,
            i_currentChainSelector
        );
    }

    function withdraw(address _beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;

        if (amount == 0) revert NothingToWithdraw();

        (bool sent, ) = _beneficiary.call{value: amount}("");

        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    function withdrawToken(
        address _beneficiary,
        address _token
    ) public onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));

        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).safeTransfer(_beneficiary, amount);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function getCCIPRouter() public view returns (address) {
        return address(i_ccipRouter);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return
            interfaceId == type(IAny2EVMMessageReceiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}

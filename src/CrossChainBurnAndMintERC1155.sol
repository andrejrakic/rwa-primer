// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC1155Core, ERC1155} from "./ERC1155Core.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Withdraw} from "./utils/Withdraw.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract CrossChainBurnAndMintERC1155 is ERC1155Core, IAny2EVMMessageReceiver, ReentrancyGuard, Withdraw {
    enum PayFeesIn {
        Native,
        LINK
    }

    error InvalidRouter(address router);
    error NotEnoughBalanceForFees(uint256 currentBalance, uint256 calculatedFees);
    error ChainNotEnabled(uint64 chainSelector);
    error SenderNotEnabled(address sender);
    error OperationNotAllowedOnCurrentChain(uint64 chainSelector);

    struct XNftDetails {
        address xNftAddress;
        bytes ccipExtraArgsBytes;
    }

    IRouterClient internal immutable i_ccipRouter;
    LinkTokenInterface internal immutable i_linkToken;
    uint64 private immutable i_currentChainSelector;

    mapping(uint64 destChainSelector => XNftDetails xNftDetailsPerChain) public s_chains;

    event ChainEnabled(uint64 chainSelector, address xNftAddress, bytes ccipExtraArgs);
    event ChainDisabled(uint64 chainSelector);
    event CrossChainSent(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes data,
        uint64 sourceChainSelector,
        uint64 destinationChainSelector
    );
    event CrossChainReceived(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes data,
        uint64 sourceChainSelector,
        uint64 destinationChainSelector
    );

    modifier onlyRouter() {
        if (msg.sender != address(i_ccipRouter)) {
            revert InvalidRouter(msg.sender);
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

    constructor(string memory uri_, address ccipRouterAddress, address linkTokenAddress, uint64 currentChainSelector)
        ERC1155Core(uri_)
    {
        i_ccipRouter = IRouterClient(ccipRouterAddress);
        i_linkToken = LinkTokenInterface(linkTokenAddress);
        i_currentChainSelector = currentChainSelector;
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
        uint256 id,
        uint256 amount,
        bytes memory data,
        uint64 destinationChainSelector,
        PayFeesIn payFeesIn
    ) external nonReentrant onlyEnabledChain(destinationChainSelector) returns (bytes32 messageId) {
        string memory tokenUri = uri(id);
        burn(from, id, amount);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(s_chains[destinationChainSelector].xNftAddress),
            data: abi.encode(from, to, id, amount, data, tokenUri),
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

        emit CrossChainSent(from, to, id, amount, data, i_currentChainSelector, destinationChainSelector);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155) returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || super.supportsInterface(interfaceId);
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
        (address from, address to, uint256 id, uint256 amount, bytes memory data, string memory tokenUri) =
            abi.decode(message.data, (address, address, uint256, uint256, bytes, string));

        mint(to, id, amount, data, tokenUri);

        emit CrossChainReceived(from, to, id, amount, data, sourceChainSelector, i_currentChainSelector);
    }
}

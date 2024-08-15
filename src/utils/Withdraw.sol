// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract Withdraw is OwnerIsCreator {
    using SafeERC20 for IERC20;

    error NothingToWithdraw();
    error FailedToWithdrawEth(address owner, address target, uint256 value);

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
}

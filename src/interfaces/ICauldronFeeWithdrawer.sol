// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/interfaces/IERC20.sol";

interface ICauldronFeeWithdrawer {
    function rescueTokens(
        IERC20 token,
        address to,
        uint256 amount
    ) external;

    function transferOwnership(
        address newOwner,
        bool direct,
        bool renounce
    ) external;
}

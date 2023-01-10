// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/interfaces/IERC20.sol";

interface ICauldronFeeBridger {
    function bridge(IERC20 token, uint256 amount) external;
}

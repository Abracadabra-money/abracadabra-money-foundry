// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "interfaces/ICauldronV3.sol";

interface ICauldronV4 is ICauldronV3 {
    function setBlacklistedCallee(address callee, bool blacklisted) external;

    function blacklistedCallees(address callee) external view returns (bool);

    function setAllowedSupplyReducer(address account, bool allowed) external;

    function isSolvent(address user) external view returns (bool);

    function isCollaterizationSafe(address user) external view returns (bool);

    function setSafeCollaterization(uint256 safeCollaterizationRate) external;

    function safeLiquidate(
        address[] memory users,
        uint256[] memory maxBorrowParts,
        address to,
        address swapper,
        bytes memory swapperData
    ) external;

    function repayForAll(uint128 amount, bool skim) external returns (uint128);
}

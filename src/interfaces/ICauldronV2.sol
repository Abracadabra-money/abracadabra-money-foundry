// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/interfaces/IERC20.sol";
import "BoringSolidity/libraries/BoringRebase.sol";
import "interfaces/IOracle.sol";

interface ICauldronV2 {
    function oracle() external view returns (IOracle);

    function oracleData() external view returns (bytes memory);

    function accrueInfo()
        external
        view
        returns (
            uint64,
            uint128,
            uint64
        );

    function BORROW_OPENING_FEE() external view returns (uint256);

    function COLLATERIZATION_RATE() external view returns (uint256);

    function LIQUIDATION_MULTIPLIER() external view returns (uint256);

    function totalCollateralShare() external view returns (uint256);

    function bentoBox() external view returns (address);

    function feeTo() external view returns (address);

    function masterContract() external view returns (ICauldronV2);

    function collateral() external view returns (IERC20);

    function setFeeTo(address newFeeTo) external;

    function accrue() external;

    function totalBorrow() external view returns (Rebase memory);

    function userBorrowPart(address account) external view returns (uint256);

    function userCollateralShare(address account) external view returns (uint256);

    function withdrawFees() external;

    function cook(
        uint8[] calldata actions,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external payable returns (uint256 value1, uint256 value2);

    function addCollateral(
        address to,
        bool skim,
        uint256 share
    ) external;

    function removeCollateral(address to, uint256 share) external;

    function borrow(address to, uint256 amount) external returns (uint256 part, uint256 share);

    function repay(
        address to,
        bool skim,
        uint256 part
    ) external returns (uint256 amount);

    function reduceSupply(uint256 amount) external;

    function magicInternetMoney() external view returns (IERC20);
}

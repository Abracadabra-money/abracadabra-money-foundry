// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "BoringSolidity/interfaces/IERC20.sol";
import "BoringSolidity/libraries/BoringRebase.sol";
import "cauldrons/CauldronV3_2.sol";
import "cauldrons/CauldronV4.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/ICauldronV3.sol";
import "interfaces/ICauldronV4.sol";

library CauldronLib {
    /// Cauldron percentages parameters are in bips unit
    /// Examples:
    ///  1 = 0.01%
    ///  10_000 = 100%
    ///  250 = 2.5%
    ///
    /// Adapted from original calculation. (variables are % values instead of bips):
    ///  ltv = ltv * 1e3;
    ///  borrowFee = borrowFee * (1e5 / 100);
    ///  interest = interest * (1e18 / (365.25 * 3600 * 24) / 100);
    ///  liquidationFee = liquidationFee * 1e3 + 1e5;
    function getCauldronParameters(
        IERC20 collateral,
        IOracle oracle,
        bytes memory oracleData,
        uint256 ltvBips,
        uint256 interestBips,
        uint256 borrowFeeBips,
        uint256 liquidationFeeBips
    ) public pure returns (bytes memory) {
        return
            abi.encode(
                collateral,
                oracle,
                oracleData,
                getInterestPerSecond(interestBips),
                liquidationFeeBips * 1e1 + 1e5,
                ltvBips * 1e1,
                borrowFeeBips * 1e1
            );
    }

    function getCauldronV4Parameters(
        IERC20 collateral,
        IOracle oracle,
        bytes memory oracleData,
        uint256 ltvBips,
        uint256 interestBips,
        uint256 borrowFeeBips,
        uint256 liquidationFeeBips,
        uint256 maxSafeLtvBips
    ) public pure returns (bytes memory) {
        return
            abi.encode(
                collateral,
                oracle,
                oracleData,
                getInterestPerSecond(interestBips),
                liquidationFeeBips * 1e1 + 1e5,
                ltvBips * 1e1,
                borrowFeeBips * 1e1,
                maxSafeLtvBips * 1e1
            );
    }

    /// @dev example: 200 is 2% interests
    function getInterestPerSecond(uint256 interestBips) public pure returns (uint64 interestsPerSecond) {
        return uint64((interestBips * 316880878) / 100); // 316880878 is the precomputed integral part of 1e18 / (36525 * 3600 * 24)
    }

    function getInterestPerYearFromInterestPerSecond(uint64 interestPerSecond) public pure returns (uint64 interestPerYearBips) {
        interestPerYearBips = (interestPerSecond * 100) / 316880878;
    }

    function getUserPositionInfo(ICauldronV2 cauldron, address account)
        internal
        view
        returns (
            uint256 ltvBips,
            uint256 borrowValue,
            uint256 collateralValue
        )
    {
        IBentoBoxV1 box = IBentoBoxV1(cauldron.bentoBox());

        // On-fly accrue interests
        Rebase memory totalBorrow = cauldron.totalBorrow();
        {
            (uint64 lastAccrued, , uint64 INTEREST_PER_SECOND) = cauldron.accrueInfo();
            uint256 elapsedTime = block.timestamp - lastAccrued;

            if (elapsedTime != 0 && totalBorrow.base != 0) {
                totalBorrow.elastic =
                    totalBorrow.elastic +
                    uint128((uint256(totalBorrow.elastic) * INTEREST_PER_SECOND * elapsedTime) / 1e18);
            }
        }
        {
            uint256 priceFeed = cauldron.oracle().peekSpot(cauldron.oracleData());

            uint256 collateralAmount = RebaseLibrary.toElastic(
                box.totals(cauldron.collateral()),
                cauldron.userCollateralShare(account),
                false
            );

            collateralValue = (collateralAmount * 1e18) / priceFeed;
        }

        borrowValue = (cauldron.userBorrowPart(account) * totalBorrow.elastic) / totalBorrow.base;
        ltvBips = (borrowValue * 1e4) / collateralValue;
    }

    function deployCauldronV3(
        IBentoBoxV1 degenBox,
        address masterContract,
        IERC20 collateral,
        IOracle oracle,
        bytes memory oracleData,
        uint256 ltvBips,
        uint256 interestBips,
        uint256 borrowFeeBips,
        uint256 liquidationFeeBips
    ) internal returns (ICauldronV3 cauldron) {
        bytes memory data = getCauldronParameters(collateral, oracle, oracleData, ltvBips, interestBips, borrowFeeBips, liquidationFeeBips);
        return ICauldronV3(IBentoBoxV1(degenBox).deploy(masterContract, data, true));
    }

    function deployCauldronV4(
        IBentoBoxV1 degenBox,
        address masterContract,
        IERC20 collateral,
        IOracle oracle,
        bytes memory oracleData,
        uint256 ltvBips,
        uint256 interestBips,
        uint256 borrowFeeBips,
        uint256 liquidationFeeBips,
        uint256 maxSafeLtvBips 
    ) internal returns (ICauldronV4 cauldron) {
        require(maxSafeLtvBips < ltvBips, "maxSafeLtvBips must be higher than ltvBips");
        
        bytes memory data = getCauldronV4Parameters(collateral, oracle, oracleData, ltvBips, interestBips, borrowFeeBips, liquidationFeeBips, maxSafeLtvBips);
        return ICauldronV4(IBentoBoxV1(degenBox).deploy(masterContract, data, true));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/interfaces/IERC20.sol";
import "interfaces/IGmxVault.sol";
import "interfaces/IGmxGlpManager.sol";

interface IVaultPriceFeed {
    function adjustmentBasisPoints(address _token) external view returns (uint256);

    function isAdjustmentAdditive(address _token) external view returns (bool);

    function setAdjustment(
        address _token,
        bool _isAdditive,
        uint256 _adjustmentBps
    ) external;

    function setUseV2Pricing(bool _useV2Pricing) external;

    function setIsAmmEnabled(bool _isEnabled) external;

    function setIsSecondaryPriceEnabled(bool _isEnabled) external;

    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints) external;

    function setSpreadThresholdBasisPoints(uint256 _spreadThresholdBasisPoints) external;

    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external;

    function setPriceSampleSpace(uint256 _priceSampleSpace) external;

    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation) external;

    function getPrice(
        address _token,
        bool _maximise,
        bool _includeAmmPrice,
        bool _useSwapPricing
    ) external view returns (uint256);

    function getAmmPrice(address _token) external view returns (uint256);
}

contract GmxLens {
    uint256 private constant BASIS_POINTS_DIVISOR = 10000;
    uint256 private constant PRICE_PRECISION = 10**30;
    uint256 private constant USDG_DECIMALS = 18;

    IGmxGlpManager public immutable manager;
    IGmxVault public immutable vault;

    IERC20 private immutable glp;
    IERC20 private immutable usdg;

    constructor(
        IGmxGlpManager _manager,
        IGmxVault _vault
    ) {
        manager = _manager;
        vault = _vault;
        glp = IERC20(manager.glp());
        usdg = IERC20(manager.usdg());
    }

    function getTokenOutFromBurningGlp(address tokenOut, uint256 glpAmount) external view returns (uint256) {
        uint256 aumInUsdg = manager.getAumInUsdg(false);
        uint256 glpSupply = glp.totalSupply();
        uint256 usdgAmount = (glpAmount * aumInUsdg) / glpSupply;
        uint256 redemptionAmount = _getRedemptionAmount(tokenOut, usdgAmount);

        usdgAmount = _decreaseUsdgAmount(tokenOut, usdgAmount);

        uint256 feeBasisPoints = _getFeeBasisPoints(
            usdgAmount,
            tokenOut,
            usdgAmount,
            vault.mintBurnFeeBasisPoints(),
            vault.taxBasisPoints(),
            false
        );

        return _collectSwapFees(redemptionAmount, feeBasisPoints);
    }

    function _collectSwapFees(uint256 _amount, uint256 _feeBasisPoints) private pure returns (uint256) {
        return (_amount * (BASIS_POINTS_DIVISOR - _feeBasisPoints)) / BASIS_POINTS_DIVISOR;
    }

    function _getFeeBasisPoints(
        uint256 initialAmount,
        address _token,
        uint256 _usdgDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) private view returns (uint256) {
        if (!vault.hasDynamicFees()) {
            return _feeBasisPoints;
        }

        uint256 nextAmount = initialAmount + _usdgDelta;
        if (!_increment) {
            nextAmount = _usdgDelta > initialAmount ? 0 : initialAmount - _usdgDelta;
        }

        uint256 targetAmount = _getTargetUsdgAmount(_token);
        if (targetAmount == 0) {
            return _feeBasisPoints;
        }

        uint256 initialDiff = initialAmount > targetAmount ? initialAmount - targetAmount : targetAmount - initialAmount;
        uint256 nextDiff = nextAmount > targetAmount ? nextAmount - targetAmount : targetAmount - nextAmount;

        if (nextDiff < initialDiff) {
            uint256 rebateBps = (_taxBasisPoints * initialDiff) / targetAmount;
            return rebateBps > _feeBasisPoints ? 0 : _feeBasisPoints - rebateBps;
        }

        uint256 averageDiff = (initialDiff + nextDiff) / 2;
        if (averageDiff > targetAmount) {
            averageDiff = targetAmount;
        }
        uint256 taxBps = (_taxBasisPoints * averageDiff) / targetAmount;
        return _feeBasisPoints + taxBps;
    }

    function _getTargetUsdgAmount(address _token) private view returns (uint256) {
        uint256 supply = IERC20(usdg).totalSupply();
        if (supply == 0) {
            return 0;
        }
        uint256 weight = vault.tokenWeights(_token);
        return (weight * supply) / vault.totalTokenWeights();
    }

    function _decreaseUsdgAmount(address _token, uint256 _amount) private view returns (uint256) {
        uint256 value = vault.usdgAmounts(_token);
        if (value <= _amount) {
            return 0;
        }
        return value - _amount;
    }

    function _getRedemptionAmount(address _token, uint256 _usdgAmount) private view returns (uint256) {
        uint256 price = _getMaxPrice(_token);
        uint256 redemptionAmount = (_usdgAmount * PRICE_PRECISION) / price;
        return _adjustForDecimals(redemptionAmount, address(usdg), _token);
    }

    function _adjustForDecimals(
        uint256 _amount,
        address _tokenDiv,
        address _tokenMul
    ) private view returns (uint256) {
        uint256 decimalsDiv = _tokenDiv == address(usdg) ? USDG_DECIMALS : vault.tokenDecimals(_tokenDiv);
        uint256 decimalsMul = _tokenMul == address(usdg) ? USDG_DECIMALS : vault.tokenDecimals(_tokenMul);
        return (_amount * 10**decimalsMul) / 10**decimalsDiv;
    }

    function _getMaxPrice(address _token) private view returns (uint256) {
        return IVaultPriceFeed(vault.priceFeed()).getPrice(_token, true, false, true);
    }
}

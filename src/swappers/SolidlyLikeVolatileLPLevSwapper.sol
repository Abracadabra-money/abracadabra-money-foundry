// SPDX-License-Identifier: MIT
// solhint-disable avoid-low-level-calls
pragma solidity >=0.8.0;

import "BoringSolidity/interfaces/IERC20.sol";
import "BoringSolidity/libraries/BoringERC20.sol";
import "interfaces/ISolidlyLpWrapper.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/ILevSwapperV2.sol";
import "interfaces/ISolidlyPair.sol";
import "interfaces/ISolidlyRouter.sol";
import "libraries/SolidlyOneSidedVolatile.sol";

/// @notice Generic LP leverage swapper for Abra Wrapped Solidly Volatile Pool using Matcha/0x aggregator
contract SolidlyLikeVolatileLPLevSwapper is ILevSwapperV2 {
    using BoringERC20 for IERC20;

    error ErrToken0SwapFailed();
    error ErrToken1SwapFailed();

    IBentoBoxV1 public immutable bentoBox;
    ISolidlyLpWrapper public immutable wrapper;
    ISolidlyPair public immutable pair;
    ISolidlyRouter public immutable router;
    IERC20 public immutable mim;
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    address public immutable zeroXExchangeProxy;

    constructor(
        IBentoBoxV1 _bentoBox,
        ISolidlyRouter _router,
        ISolidlyLpWrapper _wrapper,
        IERC20 _mim,
        address _zeroXExchangeProxy
    ) {
        bentoBox = _bentoBox;
        router = _router;
        wrapper = _wrapper;

        ISolidlyPair _pair = ISolidlyPair(address(_wrapper.underlying()));
        mim = _mim;
        zeroXExchangeProxy = _zeroXExchangeProxy;

        IERC20 _token0 = IERC20(_pair.token0());
        IERC20 _token1 = IERC20(_pair.token1());
        token0 = _token0;
        token1 = _token1;

        IERC20(address(_pair)).approve(address(_wrapper), type(uint256).max);
        _token0.approve(address(_router), type(uint256).max);
        _token1.approve(address(_router), type(uint256).max);
        _mim.approve(_zeroXExchangeProxy, type(uint256).max);

        pair = _pair;
    }

    /// @inheritdoc ILevSwapperV2
    function swap(
        address recipient,
        uint256 shareToMin,
        uint256 shareFrom,
        bytes calldata data
    ) external override returns (uint256 extraShare, uint256 shareReturned) {
        // 0: MIM -> token0
        // 1: MIM -> token1
        (bytes[] memory swapData, uint256 minOneSideableAmount0, uint256 minOneSideableAmount1, uint256 fee) = abi.decode(
            data,
            (bytes[], uint256, uint256, uint256)
        );

        bentoBox.withdraw(mim, address(this), address(this), 0, shareFrom);

        {
            // MIM -> token0
            (bool success, ) = zeroXExchangeProxy.call(swapData[0]);
            if (!success) {
                revert ErrToken0SwapFailed();
            }

            // MIM -> token1
            (success, ) = zeroXExchangeProxy.call(swapData[1]);
            if (!success) {
                revert ErrToken1SwapFailed();
            }
        }

        uint256 liquidity;

        {
            SolidlyOneSidedVolatile.AddLiquidityAndOneSideRemainingParams memory params = SolidlyOneSidedVolatile
                .AddLiquidityAndOneSideRemainingParams(
                    router,
                    pair,
                    address(token0),
                    address(token1),
                    pair.reserve0(),
                    pair.reserve1(),
                    token0.balanceOf(address(this)),
                    token1.balanceOf(address(this)),
                    minOneSideableAmount0,
                    minOneSideableAmount1,
                    address(this),
                    fee
                );

            (, , liquidity) = SolidlyOneSidedVolatile.addLiquidityAndOneSideRemaining(params);
        }

        liquidity = wrapper.enterFor(liquidity, address(bentoBox));
        (, shareReturned) = bentoBox.deposit(IERC20(address(wrapper)), address(bentoBox), recipient, liquidity, 0);
        extraShare = shareReturned - shareToMin;
    }
}

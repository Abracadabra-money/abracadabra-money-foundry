// SPDX-License-Identifier: MIT
// solhint-disable avoid-low-level-calls
pragma solidity >=0.8.0;

import "BoringSolidity/interfaces/IERC20.sol";
import "BoringSolidity/libraries/BoringERC20.sol";
import "interfaces/ISolidlyLpWrapper.sol";
import "interfaces/ISolidlyPair.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/ISwapperV2.sol";

/// @notice Generic LP swapper for Abra Wrapped Solidly Volatile Pool using Matcha/0x aggregator
contract SolidlyLikeVolatileLPSwapper is ISwapperV2 {
    using BoringERC20 for IERC20;

    error ErrToken0SwapFailed();
    error ErrToken1SwapFailed();

    IBentoBoxV1 public immutable bentoBox;
    ISolidlyLpWrapper public immutable wrapper;
    ISolidlyPair public immutable pair;
    IERC20 public immutable mim;

    address public immutable zeroXExchangeProxy;

    constructor(
        IBentoBoxV1 _bentoBox,
        ISolidlyLpWrapper _wrapper,
        IERC20 _mim,
        address _zeroXExchangeProxy
    ) {
        bentoBox = _bentoBox;
        wrapper = _wrapper;
        mim = _mim;
        zeroXExchangeProxy = _zeroXExchangeProxy;
        pair = ISolidlyPair(address(_wrapper.underlying()));

        IERC20(pair.token0()).approve(_zeroXExchangeProxy, type(uint256).max);
        IERC20(pair.token1()).approve(_zeroXExchangeProxy, type(uint256).max);

        mim.approve(address(_bentoBox), type(uint256).max);
    }

    /// @inheritdoc ISwapperV2
    function swap(
        address,
        address,
        address recipient,
        uint256 shareToMin,
        uint256 shareFrom,
        bytes calldata data
    ) public override returns (uint256 extraShare, uint256 shareReturned) {
        // 0: token0 -> MIM
        // 1: token1 -> MIM
        bytes[] memory swapData = abi.decode(data, (bytes[]));

        (uint256 amountFrom, ) = bentoBox.withdraw(IERC20(address(wrapper)), address(this), address(this), 0, shareFrom);

        // Wrapper -> Solidly Pair
        wrapper.leaveTo(amountFrom, address(pair));

        // Solidly Pair -> Token0, Token1
        pair.burn(address(this));

        // token0 -> MIM
        (bool success, ) = zeroXExchangeProxy.call(swapData[0]);
        if (!success) {
            revert ErrToken0SwapFailed();
        }

        // token1 -> MIM
        (success, ) = zeroXExchangeProxy.call(swapData[1]);
        if (!success) {
            revert ErrToken1SwapFailed();
        }

        (, shareReturned) = bentoBox.deposit(mim, address(this), recipient, mim.balanceOf(address(this)), 0);
        extraShare = shareReturned - shareToMin;
    }
}

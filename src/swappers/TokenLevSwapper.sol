// SPDX-License-Identifier: MIT
// solhint-disable avoid-low-level-calls
pragma solidity >=0.8.0;

import "BoringSolidity/interfaces/IERC20.sol";
import "BoringSolidity/libraries/BoringERC20.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/ILevSwapperV2.sol";

/// @notice LP leverage swapper for tokens using Matcha/0x aggregator
contract TokenLevSwapper is ILevSwapperV2 {
    using BoringERC20 for IERC20;

    error ErrSwapFailed();

    IBentoBoxV1 public immutable bentoBox;
    IERC20 public immutable mim;
    IERC20 public immutable token;
    address public immutable zeroXExchangeProxy;

    constructor(
        IBentoBoxV1 _bentoBox,
        IERC20 _token,
        IERC20 _mim,
        address _zeroXExchangeProxy
    ) {
        bentoBox = _bentoBox;
        token = _token;
        mim = _mim;
        zeroXExchangeProxy = _zeroXExchangeProxy;
        _token.approve(address(_bentoBox), type(uint256).max);
        _mim.approve(_zeroXExchangeProxy, type(uint256).max);
    }

    /// @inheritdoc ILevSwapperV2
    function swap(
        address recipient,
        uint256 shareToMin,
        uint256 shareFrom,
        bytes calldata swapData
    ) external override returns (uint256 extraShare, uint256 shareReturned) {
        bentoBox.withdraw(mim, address(this), address(this), 0, shareFrom);

        // MIM -> token
        (bool success, ) = zeroXExchangeProxy.call(swapData);
        if (!success) {
            revert ErrSwapFailed();
        }

        (, shareReturned) = bentoBox.deposit(token, address(this), recipient, token.balanceOf(address(this)), 0);
        extraShare = shareReturned - shareToMin;
    }
}

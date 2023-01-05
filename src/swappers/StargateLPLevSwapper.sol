// SPDX-License-Identifier: MIT
// solhint-disable avoid-low-level-calls
pragma solidity >=0.8.0;

import "BoringSolidity/interfaces/IERC20.sol";
import "BoringSolidity/libraries/BoringERC20.sol";
import "interfaces/IUniswapV2Pair.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/ILevSwapperV2.sol";
import "interfaces/IStargatePool.sol";
import "interfaces/IStargateRouter.sol";

/// @notice LP leverage swapper for Stargate LP using Matcha/0x aggregator
contract StargateLPLevSwapper is ILevSwapperV2 {
    using BoringERC20 for IERC20;

    error ErrSwapFailed();

    IBentoBoxV1 public immutable bentoBox;
    IStargatePool public immutable pool;
    IERC20 public immutable mim;
    IERC20 public immutable underlyingToken;
    IStargateRouter public immutable stargateRouter;
    address public immutable zeroXExchangeProxy;
    uint256 public immutable poolId;

    constructor(
        IBentoBoxV1 _bentoBox,
        IStargatePool _pool,
        uint256 _poolId,
        IStargateRouter _stargateRouter,
        IERC20 _mim,
        address _zeroXExchangeProxy
    ) {
        bentoBox = _bentoBox;
        pool = _pool;
        poolId = _poolId;
        mim = _mim;
        stargateRouter = _stargateRouter;
        zeroXExchangeProxy = _zeroXExchangeProxy;
        IERC20 _underlyingToken = IERC20(_pool.token());
        underlyingToken = _underlyingToken;

        _underlyingToken.approve(address(_stargateRouter), type(uint256).max);
        _pool.approve(address(_bentoBox), type(uint256).max);
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

        // MIM -> underlyingToken
        (bool success, ) = zeroXExchangeProxy.call(swapData);
        if (!success) {
            revert ErrSwapFailed();
        }

        // Underlying Token -> Stargate Pool LP
        stargateRouter.addLiquidity(poolId, underlyingToken.balanceOf(address(this)), address(this));
        uint256 amount = pool.balanceOf(address(this));
        
        (, shareReturned) = bentoBox.deposit(IERC20(address(pool)), address(this), recipient, amount, 0);
        extraShare = shareReturned - shareToMin;
    }
}

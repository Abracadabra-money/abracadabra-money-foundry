// SPDX-License-Identifier: MIT
// solhint-disable avoid-low-level-calls
pragma solidity >=0.8.0;

import "BoringSolidity/interfaces/IERC20.sol";
import "BoringSolidity/libraries/BoringERC20.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/ISwapperV2.sol";
import "interfaces/IGmxGlpRewardRouter.sol";
import "interfaces/IERC4626.sol";

contract GLPVaultSwapper is ISwapperV2 {
    using BoringERC20 for IERC20;

    error ErrSwapFailed();

    IBentoBoxV1 public immutable bentoBox;
    IERC20 public immutable magicGlp;
    IERC20 public immutable mim;
    IERC20 public immutable usdc;
    IERC20 public immutable sGLP;
    IGmxGlpRewardRouter public immutable glpRewardRouter;
    address public immutable zeroXExchangeProxy;

    constructor(
        IBentoBoxV1 _bentoBox,
        IERC20 _magicGlp,
        IERC20 _mim,
        IERC20 _sGLP,
        IERC20 _usdc,
        IGmxGlpRewardRouter _glpRewardRouter,
        address _zeroXExchangeProxy
    ) {
        bentoBox = _bentoBox;
        magicGlp = _magicGlp;
        mim = _mim;
        usdc = _usdc;
        sGLP = _sGLP;
        glpRewardRouter = _glpRewardRouter;
        zeroXExchangeProxy = _zeroXExchangeProxy;
        usdc.approve(_zeroXExchangeProxy, type(uint256).max);
        mim.approve(address(_bentoBox), type(uint256).max);
    }

    /// @inheritdoc ISwapperV2
    function swap(
        address,
        address,
        address recipient,
        uint256 shareToMin,
        uint256 shareFrom,
        bytes calldata swapData
    ) public override returns (uint256 extraShare, uint256 shareReturned) {
        (uint256 amount, ) = bentoBox.withdraw(IERC20(address(magicGlp)), address(this), address(this), 0, shareFrom);
        IERC4626(address(magicGlp)).withdraw(amount, address(this), address(this));

        glpRewardRouter.unstakeAndRedeemGlp(address(usdc), amount, 0, address(this));

        // USDC -> MIM
        (bool success, ) = zeroXExchangeProxy.call(swapData);
        if (!success) {
            revert ErrSwapFailed();
        }

        // we can expect dust from both gmx and 0x
        usdc.safeTransfer(recipient, usdc.balanceOf(address(this)));

        (, shareReturned) = bentoBox.deposit(mim, address(this), recipient, mim.balanceOf(address(this)), 0);
        extraShare = shareReturned - shareToMin;
    }
}

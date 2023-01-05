// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/libraries/BoringERC20.sol";
import "BoringSolidity/BoringOwnable.sol";
import {GmxGlpVaultData} from "tokens/GmxGlpVault.sol";
import "interfaces/IGmxGlpManager.sol";
import "interfaces/IGmxRewardRouterV2.sol";
import "interfaces/IGmxStakedGlp.sol";
import "interfaces/IGmxVester.sol";
import "interfaces/IGmxGlpVaultRewardHandler.sol";

/// @dev in case of V2, if adding new variable create GmxGlpVaultRewardHandlerDataV2 that inherits
/// from GmxGlpVaultRewardHandlerDataV1
contract GmxGlpVaultRewardHandlerDataV1 is GmxGlpVaultData {
    /// @dev V1 variables, do not change.
    IGmxRewardRouterV2 public rewardRouter;
}

/// @dev When making a new version, never change existing variables, always add after
/// the existing one. Ex: Inherit from GmxGlpVaultRewardHandlerDataV2 in case of a V2 version.
contract GmxGlpVaultRewardHandler is GmxGlpVaultRewardHandlerDataV1, IGmxGlpVaultRewardHandler {
    using BoringERC20 for IERC20;

    event LogRewardRouterChanged(IGmxRewardRouterV2 indexed previous, IGmxRewardRouterV2 indexed current);

    ////////////////////////////////////////////////////////////////////////////////
    /// @dev Avoid adding storage variable here
    /// Should use GmxGlpVaultData instead.
    ////////////////////////////////////////////////////////////////////////////////

    function harvest() external onlyStrategyExecutor {
        rewardRouter.handleRewards({
            shouldClaimGmx: true,
            shouldStakeGmx: true,
            shouldClaimEsGmx: true,
            shouldStakeEsGmx: true,
            shouldStakeMultiplierPoints: true,
            shouldClaimWeth: true,
            shouldConvertWethToEth: false
        });
    }

    function setRewardRouter(IGmxRewardRouterV2 _rewardRouter) external onlyOwner {
        emit LogRewardRouterChanged(rewardRouter, _rewardRouter);
        rewardRouter = _rewardRouter;
    }

    function setTokenAllowance(IERC20 token, address spender, uint256 amount) external onlyOwner {
        token.approve(spender, amount);
    }

    ///////////////////////////////////////////////////////////////////////
    // esGMX Vesting Handling
    // Adapted from RageTrade contract code

    /// @notice unstakes and vest protocol esGmx to convert it to Gmx
    function unstakeGmx(uint256 amount, uint256 amountToTransferToSender, address recipient) external onlyOwner {
        IERC20 gmx = IERC20(rewardRouter.gmx());

        if (amount > 0) {
            rewardRouter.unstakeGmx(amount);
        }
        if (amountToTransferToSender > 0) {
            uint256 gmxAmount = gmx.balanceOf(address(this));

            if (amountToTransferToSender < gmxAmount) {
                gmxAmount = amountToTransferToSender;
            }

            gmx.safeTransfer(recipient, gmxAmount);
        }
    }

    /// @notice unstakes and vest protocol esGmx to convert it to Gmx
    function unstakeEsGmxAndVest(
        uint256 amount,
        uint256 glpVesterDepositAmount,
        uint256 gmxVesterDepositAmount
    ) external onlyOwner {
        if (amount > 0) {
            rewardRouter.unstakeEsGmx(amount);
        }
        if (glpVesterDepositAmount > 0) {
            IGmxVester(rewardRouter.glpVester()).deposit(glpVesterDepositAmount);
        }
        if (gmxVesterDepositAmount > 0) {
            IGmxVester(rewardRouter.gmxVester()).deposit(gmxVesterDepositAmount);
        }
    }

    /// @notice claims vested gmx tokens (i.e. stops vesting esGmx so that the relevant glp amount is unlocked)
    /// This will withdraw and unreserve all tokens as well as pause vesting. esGMX tokens that have been converted
    /// to GMX will remain as GMX tokens.
    function withdrawFromVesting(
        bool withdrawFromGlpVester,
        bool withdrawFromGmxVester,
        bool stake
    ) external onlyOwner {
        if (withdrawFromGlpVester) {
            IGmxVester(rewardRouter.glpVester()).withdraw();
        }
        if (withdrawFromGmxVester) {
            IGmxVester(rewardRouter.gmxVester()).withdraw();
        }

        if (stake) {
            uint256 esGmxWithdrawn = IERC20(rewardRouter.esGmx()).balanceOf(address(this));
            rewardRouter.stakeEsGmx(esGmxWithdrawn);
        }
    }

    /// @notice claims vested gmx tokens and optionnaly stake or transfer to feeRecipient
    /// @dev vested esGmx gets converted to GMX every second, so whatever amount is vested gets claimed
    function claimVestedGmx(
        bool withdrawFromGlpVester,
        bool withdrawFromGmxVester,
        bool stake,
        bool transferToOwner
    ) external onlyOwner {
        IERC20 gmx = IERC20(rewardRouter.gmx());

        if (withdrawFromGlpVester) {
            IGmxVester(rewardRouter.glpVester()).claim();
        }
        if (withdrawFromGmxVester) {
            IGmxVester(rewardRouter.gmxVester()).claim();
        }

        uint256 gmxAmount = gmx.balanceOf(address(this));

        if (stake) {
            gmx.approve(address(rewardRouter.stakedGmxTracker()), gmxAmount);
            rewardRouter.stakeGmx(gmxAmount);
        } else if (transferToOwner) {
            gmx.safeTransfer(owner, gmxAmount);
        }
    }
}

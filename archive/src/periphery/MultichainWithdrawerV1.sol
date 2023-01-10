// SPDX-License-Identifier: MIXED
pragma solidity >=0.8.0;

import "BoringSolidity/interfaces/IERC20.sol";
import "BoringSolidity/BoringOwnable.sol";
import "BoringSolidity/libraries/BoringERC20.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/IAnyswapRouter.sol";
import "interfaces/ICauldronV1.sol";
import "interfaces/ICauldronV2.sol";

contract MultichainWithdrawer is BoringOwnable {
    using BoringERC20 for IERC20;

    event MimWithdrawn(uint256 amount);

    bytes4 private constant SIG_TRANSFER = 0xa9059cbb; // transfer(address,uint256)

    IBentoBoxV1 public immutable bentoBox;
    IBentoBoxV1 public immutable degenBox;
    IERC20 public immutable MIM;

    IAnyswapRouter public immutable anyswapRouter;

    address public immutable mimProvider;
    address public immutable ethereumRecipient;

    ICauldronV1[] public bentoBoxCauldronsV1;
    ICauldronV2[] public bentoBoxCauldronsV2;
    ICauldronV2[] public degenBoxCauldrons;

    constructor(
        IBentoBoxV1 bentoBox_,
        IBentoBoxV1 degenBox_,
        IERC20 mim,
        IAnyswapRouter anyswapRouter_,
        address mimProvider_,
        address ethereumRecipient_,
        ICauldronV2[] memory bentoBoxCauldronsV2_,
        ICauldronV1[] memory bentoBoxCauldronsV1_,
        ICauldronV2[] memory degenBoxCauldrons_
    ) {
        bentoBox = bentoBox_;
        degenBox = degenBox_;
        MIM = mim;
        anyswapRouter = anyswapRouter_;
        mimProvider = mimProvider_;
        ethereumRecipient = ethereumRecipient_;

        bentoBoxCauldronsV2 = bentoBoxCauldronsV2_;
        bentoBoxCauldronsV1 = bentoBoxCauldronsV1_;
        degenBoxCauldrons = degenBoxCauldrons_;

        MIM.approve(address(anyswapRouter), type(uint256).max);
    }

    function withdraw() public {
        uint256 length = bentoBoxCauldronsV2.length;
        for (uint256 i = 0; i < length; i++) {
            require(bentoBoxCauldronsV2[i].masterContract().feeTo() == address(this), "wrong feeTo");

            bentoBoxCauldronsV2[i].accrue();
            (, uint256 feesEarned, ) = bentoBoxCauldronsV2[i].accrueInfo();
            if (feesEarned > (bentoBox.toAmount(MIM, bentoBox.balanceOf(MIM, address(bentoBoxCauldronsV2[i])), false))) {
                MIM.safeTransferFrom(mimProvider, address(bentoBox), feesEarned);
                bentoBox.deposit(MIM, address(bentoBox), address(bentoBoxCauldronsV2[i]), feesEarned, 0);
            }

            bentoBoxCauldronsV2[i].withdrawFees();
        }

        length = bentoBoxCauldronsV1.length;
        for (uint256 i = 0; i < length; i++) {
            require(bentoBoxCauldronsV1[i].masterContract().feeTo() == address(this), "wrong feeTo");

            bentoBoxCauldronsV1[i].accrue();
            (, uint256 feesEarned) = bentoBoxCauldronsV1[i].accrueInfo();
            if (feesEarned > (bentoBox.toAmount(MIM, bentoBox.balanceOf(MIM, address(bentoBoxCauldronsV1[i])), false))) {
                MIM.safeTransferFrom(mimProvider, address(bentoBox), feesEarned);
                bentoBox.deposit(MIM, address(bentoBox), address(bentoBoxCauldronsV1[i]), feesEarned, 0);
            }
            bentoBoxCauldronsV1[i].withdrawFees();
        }

        length = degenBoxCauldrons.length;
        for (uint256 i = 0; i < length; i++) {
            require(degenBoxCauldrons[i].masterContract().feeTo() == address(this), "wrong feeTo");

            degenBoxCauldrons[i].accrue();
            (, uint256 feesEarned, ) = degenBoxCauldrons[i].accrueInfo();
            if (feesEarned > (degenBox.toAmount(MIM, degenBox.balanceOf(MIM, address(degenBoxCauldrons[i])), false))) {
                MIM.safeTransferFrom(mimProvider, address(degenBox), feesEarned);
                degenBox.deposit(MIM, address(degenBox), address(degenBoxCauldrons[i]), feesEarned, 0);
            }
            degenBoxCauldrons[i].withdrawFees();
        }

        uint256 mimFromBentoBoxShare = address(bentoBox) != address(0) ? bentoBox.balanceOf(MIM, address(this)) : 0;
        uint256 mimFromDegenBoxShare = address(degenBox) != address(0) ? degenBox.balanceOf(MIM, address(this)) : 0;

        withdrawFromBentoBoxes(mimFromBentoBoxShare, mimFromDegenBoxShare);

        uint256 amountWithdrawn = MIM.balanceOf(address(this));
        bridgeMimToEthereum(amountWithdrawn);

        emit MimWithdrawn(amountWithdrawn);
    }

    function withdrawFromBentoBoxes(uint256 amountBentoboxShare, uint256 amountDegenBoxShare) public {
        if (amountBentoboxShare > 0) {
            bentoBox.withdraw(MIM, address(this), address(this), 0, amountBentoboxShare);
        }
        if (amountDegenBoxShare > 0) {
            degenBox.withdraw(MIM, address(this), address(this), 0, amountDegenBoxShare);
        }
    }

    function bridgeMimToEthereum(uint256 amount) public {
        // bridge all MIM to Ethereum, chainId 1
        anyswapRouter.anySwapOut(address(MIM), ethereumRecipient, amount, 1);
    }

    function rescueTokens(
        IERC20 token,
        address to,
        uint256 amount
    ) external onlyOwner {
        token.safeTransfer(to, amount);
    }

    function addPool(ICauldronV2 pool) external onlyOwner {
        _addPool(pool);
    }

    function addPoolV1(ICauldronV1 pool) external onlyOwner {
        bentoBoxCauldronsV1.push(pool);
    }

    function addPools(ICauldronV2[] memory pools) external onlyOwner {
        for (uint256 i = 0; i < pools.length; i++) {
            _addPool(pools[i]);
        }
    }

    function _addPool(ICauldronV2 pool) internal onlyOwner {
        require(address(pool) != address(0), "invalid cauldron");

        if (pool.bentoBox() == address(bentoBox)) {
            //do not allow doubles
            for (uint256 i = 0; i < bentoBoxCauldronsV2.length; i++) {
                require(bentoBoxCauldronsV2[i] != pool, "already added");
            }
            bentoBoxCauldronsV2.push(pool);
        } else if (pool.bentoBox() == address(degenBox)) {
            for (uint256 i = 0; i < degenBoxCauldrons.length; i++) {
                require(degenBoxCauldrons[i] != pool, "already added");
            }
            degenBoxCauldrons.push(pool);
        }
    }
}

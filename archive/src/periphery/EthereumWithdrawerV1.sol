// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/BoringOwnable.sol";
import "BoringSolidity/libraries/BoringERC20.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/IAnyswapRouter.sol";
import "interfaces/ICauldronV1.sol";
import "interfaces/ICauldronV2.sol";

contract EthereumWithdrawer is BoringOwnable {
    using BoringERC20 for IERC20;

    event SwappedMimToSpell(uint256 amountSushiswap, uint256 amountUniswap, uint256 total);
    event MimWithdrawn(uint256 bentoxBoxAmount, uint256 degenBoxAmount, uint256 total);

    IBentoBoxV1 public constant BENTOBOX = IBentoBoxV1(0xF5BCE5077908a1b7370B9ae04AdC565EBd643966);
    IBentoBoxV1 public constant DEGENBOX = IBentoBoxV1(0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce);

    IERC20 public constant MIM = IERC20(0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3);
    IERC20 public constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address public constant SPELL = 0x090185f2135308BaD17527004364eBcC2D37e5F6;
    address public constant sSPELL = 0x26FA3fFFB6EfE8c1E69103aCb4044C26B9A106a9;

    address public constant MIM_PROVIDER = 0x5f0DeE98360d8200b20812e174d139A1a633EDd2;
    address public constant TREASURY = 0x5A7C5505f3CFB9a0D9A8493EC41bf27EE48c406D;

    ICauldronV1[] public bentoBoxCauldronsV1;
    ICauldronV2[] public bentoBoxCauldronsV2;
    ICauldronV2[] public degenBoxCauldrons;

    uint256 public treasuryShare;

    mapping(address => bool) public verified;

    constructor(
        ICauldronV2[] memory bentoBoxCauldronsV2_,
        ICauldronV1[] memory bentoBoxCauldronsV1_,
        ICauldronV2[] memory degenBoxCauldrons_
    ) {
        bentoBoxCauldronsV2 = bentoBoxCauldronsV2_;
        bentoBoxCauldronsV1 = bentoBoxCauldronsV1_;
        degenBoxCauldrons = degenBoxCauldrons_;

        verified[msg.sender] = true;
        treasuryShare = 25;
    }

    modifier onlyVerified() {
        require(verified[msg.sender], "Only verified operators");
        _;
    }

    function withdraw() public {
        uint256 length = bentoBoxCauldronsV2.length;
        for (uint256 i = 0; i < length; i++) {
            require(bentoBoxCauldronsV2[i].masterContract().feeTo() == address(this), "wrong feeTo");

            bentoBoxCauldronsV2[i].accrue();
            (, uint256 feesEarned, ) = bentoBoxCauldronsV2[i].accrueInfo();
            if (feesEarned > (BENTOBOX.toAmount(MIM, BENTOBOX.balanceOf(MIM, address(bentoBoxCauldronsV2[i])), false))) {
                MIM.safeTransferFrom(MIM_PROVIDER, address(BENTOBOX), feesEarned);
                BENTOBOX.deposit(MIM, address(BENTOBOX), address(bentoBoxCauldronsV2[i]), feesEarned, 0);
            }

            bentoBoxCauldronsV2[i].withdrawFees();
        }

        length = bentoBoxCauldronsV1.length;
        for (uint256 i = 0; i < length; i++) {
            require(bentoBoxCauldronsV1[i].masterContract().feeTo() == address(this), "wrong feeTo");

            bentoBoxCauldronsV1[i].accrue();
            (, uint256 feesEarned) = bentoBoxCauldronsV1[i].accrueInfo();
            if (feesEarned > (BENTOBOX.toAmount(MIM, BENTOBOX.balanceOf(MIM, address(bentoBoxCauldronsV1[i])), false))) {
                MIM.safeTransferFrom(MIM_PROVIDER, address(BENTOBOX), feesEarned);
                BENTOBOX.deposit(MIM, address(BENTOBOX), address(bentoBoxCauldronsV1[i]), feesEarned, 0);
            }
            bentoBoxCauldronsV1[i].withdrawFees();
        }

        length = degenBoxCauldrons.length;
        for (uint256 i = 0; i < length; i++) {
            require(degenBoxCauldrons[i].masterContract().feeTo() == address(this), "wrong feeTo");

            degenBoxCauldrons[i].accrue();
            (, uint256 feesEarned, ) = degenBoxCauldrons[i].accrueInfo();
            if (feesEarned > (DEGENBOX.toAmount(MIM, DEGENBOX.balanceOf(MIM, address(degenBoxCauldrons[i])), false))) {
                MIM.safeTransferFrom(MIM_PROVIDER, address(DEGENBOX), feesEarned);
                DEGENBOX.deposit(MIM, address(DEGENBOX), address(degenBoxCauldrons[i]), feesEarned, 0);
            }
            degenBoxCauldrons[i].withdrawFees();
        }

        uint256 mimFromBentoBoxShare = BENTOBOX.balanceOf(MIM, address(this));
        uint256 mimFromDegenBoxShare = DEGENBOX.balanceOf(MIM, address(this));
        withdrawFromBentoBoxes(mimFromBentoBoxShare, mimFromDegenBoxShare);

        uint256 mimFromBentoBox = BENTOBOX.toAmount(MIM, mimFromBentoBoxShare, false);
        uint256 mimFromDegenBox = DEGENBOX.toAmount(MIM, mimFromDegenBoxShare, false);
        emit MimWithdrawn(mimFromBentoBox, mimFromDegenBox, mimFromBentoBox + mimFromDegenBox);
    }

    function withdrawFromBentoBoxes(uint256 amountBentoboxShare, uint256 amountDegenBoxShare) public {
        BENTOBOX.withdraw(MIM, address(this), address(this), 0, amountBentoboxShare);
        DEGENBOX.withdraw(MIM, address(this), address(this), 0, amountDegenBoxShare);
    }

    function rescueTokens(
        IERC20 token,
        address to,
        uint256 amount
    ) external onlyOwner {
        token.safeTransfer(to, amount);
    }

    function setTreasuryShare(uint256 share) external onlyOwner {
        treasuryShare = share;
    }

    function swapMimForSpell1Inch(address inchrouter, bytes calldata data) external onlyOwner {
        MIM.approve(inchrouter, type(uint256).max);
        (bool success, ) = inchrouter.call(data);
        require(success, "1inch swap unsucessful");
        IERC20(SPELL).safeTransfer(address(sSPELL), IERC20(SPELL).balanceOf(address(this)));
        MIM.approve(inchrouter, 0);
    }

    function setVerified(address operator, bool status) external onlyOwner {
        verified[operator] = status;
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

        if (pool.bentoBox() == address(BENTOBOX)) {
            for (uint256 i = 0; i < bentoBoxCauldronsV2.length; i++) {
                require(bentoBoxCauldronsV2[i] != pool, "already added");
            }
            bentoBoxCauldronsV2.push(pool);
        } else if (pool.bentoBox() == address(DEGENBOX)) {
            for (uint256 i = 0; i < degenBoxCauldrons.length; i++) {
                require(degenBoxCauldrons[i] != pool, "already added");
            }
            degenBoxCauldrons.push(pool);
        }
    }
}

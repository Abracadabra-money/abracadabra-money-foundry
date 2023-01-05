// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "utils/BaseScript.sol";
import "cauldrons/CauldronV4.sol";
import "utils/CauldronLib.sol";
import "oracles/ProxyOracle.sol";
import "periphery/CauldronOwner.sol";
import "interfaces/IGmxRewardRouterV2.sol";
import "interfaces/IGmxGlpRewardRouter.sol";
import "interfaces/IWETH.sol";
import "tokens/GmxGlpVault.sol";
import "periphery/GmxGlpVaultRewardHandler.sol";
import "periphery/DegenBoxERC4626Wrapper.sol";
import "periphery/GlpVaultHarvestor.sol";
import "oracles/GLPVaultOracle.sol";
import "swappers/GLPVaultSwapper.sol";
import "swappers/GLPVaultLevSwapper.sol";

contract GlpCauldronCompScript is BaseScript {
    function run()
        public
        returns (
            ICauldronV4 cauldron,
            GmxGlpVault vault,
            GlpVaultHarvestor harvestor,
            ProxyOracle oracle
        )
    {
        if (block.chainid == ChainId.Arbitrum) {
            address safe = constants.getAddress("arbitrum.safe.ops");
            address sGlp = constants.getAddress("arbitrum.gmx.sGLP");
            address degenBox = constants.getAddress("arbitrum.degenBox");
            address masterContract = constants.getAddress("arbitrum.cauldronV4");
            address weth = constants.getAddress("arbitrum.weth");
            address glpManager = constants.getAddress("arbitrum.gmx.glpManager");
            address rewardRouterV2 = constants.getAddress("arbitrum.gmx.rewardRouterV2");
            address glpRewardRouter = constants.getAddress("arbitrum.gmx.glpRewardRouter");

            startBroadcast();

            vault = new GmxGlpVault(ERC20(sGlp), "magicGLP", "mGLP");
            GLPVaultOracle oracleImpl = new GLPVaultOracle(
                IGmxGlpManager(glpManager),
                IERC20(constants.getAddress("arbitrum.gmx.glp")),
                IERC4626(vault)
            );

            oracle = new ProxyOracle();
            oracle.changeOracleImplementation(IOracle(oracleImpl));
            cauldron = CauldronLib.deployCauldronV4(
                IBentoBoxV1(degenBox),
                masterContract,
                vault,
                oracle,
                "",
                7500, // 75% ltv
                0, // 0% interests
                0, // 0% opening
                750 // 7.5% liquidation
            );

            // Periphery contract used to atomically wrap and deposit to degenbox
            new DegenBoxERC4626Wrapper(IBentoBoxV1(degenBox), vault);

            GmxGlpVaultRewardHandler rewardHandler = new GmxGlpVaultRewardHandler();
            rewardHandler.transferOwnership(address(0), true, true); // owner is only from the sGlp wrapper
            vault.setRewardHandler(address(rewardHandler));

            // Use to facilitate collecting and swapping rewards to the distributor & distribute
            harvestor = new GlpVaultHarvestor(
                IWETH(weth),
                IGmxRewardRouterV2(rewardRouterV2),
                IGmxGlpRewardRouter(glpRewardRouter),
                IGmxGlpVaultRewardHandler(address(vault))
            );
            harvestor.setOperator(constants.getAddress("arbitrum.safe.devOps.gelatoProxy"), true);

            vault.setStrategyExecutor(address(harvestor), true);

            GmxGlpVaultRewardHandler(address(vault)).setRewardRouter(IGmxRewardRouterV2(rewardRouterV2));
            GmxGlpVaultRewardHandler(address(vault)).setTokenAllowance(IERC20(weth), address(harvestor), type(uint256).max);

            new GLPVaultSwapper(
                IBentoBoxV1(degenBox),
                ERC20(address(vault)),
                IERC20(constants.getAddress("arbitrum.mim")),
                IERC20(sGlp),
                IERC20(constants.getAddress("arbitrum.usdc")),
                IGmxGlpRewardRouter(glpRewardRouter),
                constants.getAddress("arbitrum.aggregators.zeroXExchangProxy")
            );
            new GLPVaultLevSwapper(
                IBentoBoxV1(degenBox),
                ERC20(address(vault)),
                IERC20(constants.getAddress("arbitrum.mim")),
                IERC20(sGlp),
                IERC20(constants.getAddress("arbitrum.usdc")),
                glpManager,
                IGmxGlpRewardRouter(glpRewardRouter),
                constants.getAddress("arbitrum.aggregators.zeroXExchangProxy")
            );

            // Only when deploying live
            if (!testing) {
                vault.transferOwnership(safe, true, false);
                harvestor.transferOwnership(safe, true, false);
                oracle.transferOwnership(safe, true, false);
            }

            stopBroadcast();
        } else {
            revert("chain not supported");
        }
    }
}

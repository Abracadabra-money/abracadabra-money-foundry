// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "utils/BaseScript.sol";
import "utils/CauldronLib.sol";
import "oracles/ProxyOracle.sol";
import "oracles/InverseOracle.sol";
import "swappers/TokenSwapper.sol";
import "swappers/TokenLevSwapper.sol";
import "strategies/LiquityStabilityPoolStrategy.sol";

contract LiquityScript is BaseScript {
    function run()
        public
        returns (
            ICauldronV3 cauldron,
            ProxyOracle oracle,
            ISwapperV2 swapper,
            ILevSwapperV2 levSwapper,
            LiquityStabilityPoolStrategy strategy
        )
    {
        address xMerlin = constants.getAddress("xMerlin");
        IBentoBoxV1 degenBox = IBentoBoxV1(constants.getAddress("mainnet.degenBox"));

        vm.startBroadcast();

        // LUSD Oracle
        oracle = ProxyOracle(0x3Cc89EA432c36c8F96731765997722192202459D);

        cauldron = CauldronLib.deployCauldronV3(
            degenBox,
            address(constants.getAddress("mainnet.cauldronV3_2")),
            IERC20(constants.getAddress("mainnet.liquity.lusd")),
            oracle,
            "",
            9500, // 95% ltv
            50, // 0.5% interests
            0, // 0% opening
            100 // 1% liquidation
        );

        swapper = new TokenSwapper(
            IBentoBoxV1(constants.getAddress("mainnet.degenBox")),
            IERC20(constants.getAddress("mainnet.liquity.lusd")),
            IERC20(constants.getAddress("mainnet.mim")),
            constants.getAddress("mainnet.aggregators.zeroXExchangProxy")
        );

        levSwapper = new TokenLevSwapper(
            IBentoBoxV1(constants.getAddress("mainnet.degenBox")),
            IERC20(constants.getAddress("mainnet.liquity.lusd")),
            IERC20(constants.getAddress("mainnet.mim")),
            constants.getAddress("mainnet.aggregators.zeroXExchangProxy")
        );

        strategy = new LiquityStabilityPoolStrategy(
            IERC20(constants.getAddress("mainnet.liquity.lusd")),
            degenBox,
            ILiquityStabilityPool(constants.getAddress("mainnet.liquity.stabilityPool"))
        );

        strategy.setRewardTokenEnabled(IERC20(address(0)), true);
        strategy.setRewardTokenEnabled(IERC20(constants.getAddress("mainnet.liquity.lqty")), true);
        strategy.setSwapper(constants.getAddress("mainnet.aggregators.zeroXExchangProxy"));

        if (!testing) {
            strategy.setStrategyExecutor(xMerlin, true);
            strategy.setFeeParameters(xMerlin, 10);
            strategy.transferOwnership(xMerlin, true, false);
        } else {
            strategy.setStrategyExecutor(deployer(), true);
        }

        vm.stopBroadcast();
    }
}

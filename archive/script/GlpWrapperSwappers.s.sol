// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "utils/BaseScript.sol";
import "cauldrons/CauldronV4.sol";
import "utils/CauldronLib.sol";
import "oracles/ProxyOracle.sol";
import "periphery/CauldronOwner.sol";
import "interfaces/IGmxRewardRouterV2.sol";
import "tokens/GmxGlpWrapper.sol";
import "periphery/GmxGlpRewardHandler.sol";
import "periphery/MimCauldronDistributor.sol";
import "periphery/DegenBoxTokenWrapper.sol";
import "periphery/GlpWrapperHarvestor.sol";
import "swappers/GLPWrapperSwapper.sol";
import "swappers/GLPWrapperLevSwapper.sol";

contract GlpWrapperSwappersScript is BaseScript {
    function run() public returns (GmxGlpWrapper wrapper) {
        if (block.chainid == ChainId.Arbitrum) {
            address sGlp = constants.getAddress("arbitrum.gmx.sGLP");
            address degenBox = constants.getAddress("arbitrum.degenBox");
            address mim = constants.getAddress("arbitrum.mim");
            address rewardRouterV2 = constants.getAddress("arbitrum.gmx.rewardRouterV2");
            address usdc = constants.getAddress("arbitrum.usdc");
            address swapper = constants.getAddress("arbitrum.aggregators.zeroXExchangProxy");
            address glpManager = constants.getAddress("arbitrum.gmx.glpManager");

            vm.startBroadcast();
            wrapper = GmxGlpWrapper(constants.getAddress("arbitrum.abracadabraWrappedStakedGlp"));
            new GLPWrapperSwapper(
                IBentoBoxV1(degenBox),
                wrapper,
                IERC20(mim),
                IERC20(sGlp),
                IERC20(usdc),
                IGmxRewardRouterV2(rewardRouterV2),
                swapper
            );
            new GLPWrapperLevSwapper(
                IBentoBoxV1(degenBox),
                wrapper,
                IERC20(mim),
                IERC20(sGlp),
                IERC20(usdc),
                glpManager,
                IGmxRewardRouterV2(rewardRouterV2),
                swapper
            );
            vm.stopBroadcast();
        } else {
            revert("chain not supported");
        }
    }
}

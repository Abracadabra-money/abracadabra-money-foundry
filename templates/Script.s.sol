// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "utils/BaseScript.sol";
import "utils/UniswapLikeLib.sol";

contract MyScript is BaseScript {
    function run() public returns (ProxyOracle oracle) {
        address xMerlin = constants.getAddress("xMerlin");

        startBroadcast();

        // Dummy deployment example
        oracle = UniswapLikeLib.deployLPOracle(
            "usdc/weth",
            IUniswapV2Pair(0x397FF1542f962076d0BFE58eA045FfA2d347ACa0), // sushi usdc/weth slp
            IAggregator(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6), // usdc chainlink
            IAggregator(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419) // weth chainlink
        );

        // Only when deploying live
        if (!testing) {
            oracle.transferOwnership(xMerlin, true, false);
        }

        stopBroadcast();
    }
}

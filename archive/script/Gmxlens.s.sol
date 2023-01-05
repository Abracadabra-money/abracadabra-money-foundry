// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "utils/BaseScript.sol";
import "interfaces/IGmxGlpManager.sol";
import "interfaces/IGmxVault.sol";
import "periphery/GmxLens.sol";

contract GmxLensScript is BaseScript {
    function run() public returns (GmxLens lens) {
        vm.startBroadcast();

        // Deployment here.
        lens = new GmxLens(
            IGmxGlpManager(constants.getAddress("arbitrum.gmx.glpManager")),
            IGmxVault(constants.getAddress("arbitrum.gmx.vault"))
        );

        vm.stopBroadcast();
    }
}

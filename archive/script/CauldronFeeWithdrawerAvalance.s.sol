// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "utils/BaseScript.sol";
import "periphery/CauldronFeeWithdrawer.sol";

contract CauldronFeeWithdrawerScript is BaseScript {
    function run() public returns (CauldronFeeWithdrawer withdrawer) {
        address xMerlin = constants.getAddress("xMerlin");

        vm.startBroadcast();

        if (getChainIdKey() == ChainId.Avalanche) {
            ERC20 mim = ERC20(constants.getAddress("avalanche.mim"));
            address mimProvider = 0xAE4D3a42E46399827bd094B4426e2f79Cca543CA; // TODO: to confirm.

            withdrawer = new CauldronFeeWithdrawer(mim);
            withdrawer.setBridgeableToken(mim, true);
            withdrawer.setBentoBox(IBentoBoxV1(constants.getAddress("avalanche.degenBox1")), true);
            withdrawer.setBentoBox(IBentoBoxV1(constants.getAddress("avalanche.degenBox2")), true);

            AnyswapCauldronFeeBridger bridger = new AnyswapCauldronFeeBridger(
                IAnyswapRouter(constants.getAddress("avalanche.anyswapRouterV4")),
                constants.getAddress("mainnet.cauldronFeeWithdrawer"),
                1
            );
            bridger.setAuthorizedCaller(address(withdrawer), true);

            withdrawer.setParameters(address(0), mimProvider, bridger);
            withdrawer.setBentoBox(IBentoBoxV1(constants.getAddress("avalanche.degenBox1")), true);
            withdrawer.setBentoBox(IBentoBoxV1(constants.getAddress("avalanche.degenBox2")), true);

            CauldronInfo[] memory cauldronInfos = constants.getCauldrons("avalanche", true);
            address[] memory cauldrons = new address[](cauldronInfos.length);
            uint8[] memory versions = new uint8[](cauldronInfos.length);
            bool[] memory enabled = new bool[](cauldronInfos.length);

            for (uint256 i = 0; i < cauldronInfos.length; i++) {
                CauldronInfo memory cauldronInfo = cauldronInfos[i];

                cauldrons[i] = cauldronInfo.cauldron;
                versions[i] = cauldronInfo.version;
                enabled[i] = true;
            }

            withdrawer.setCauldrons(cauldrons, versions, enabled);
        }

        // Only when deploying live
        if (!testing) {
            withdrawer.transferOwnership(xMerlin, true, false);
        }

        vm.stopBroadcast();
    }
}

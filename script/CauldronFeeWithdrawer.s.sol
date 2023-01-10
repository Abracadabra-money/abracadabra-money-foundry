// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "utils/BaseScript.sol";
import "periphery/CauldronFeeWithdrawer.sol";
import "periphery/MSpellSender.sol";

contract CauldronFeeWithdrawerScript is BaseScript {
    function run() public returns (CauldronFeeWithdrawer withdrawer) {
        vm.startBroadcast();

        IERC20 mim = IERC20(constants.getAddress("mainnet.mim"));
        address spell = constants.getAddress("mainnet.spell");
        address sSpell = constants.getAddress("mainnet.sSpell");
        address mimProvider = 0x5f0DeE98360d8200b20812e174d139A1a633EDd2;

        withdrawer = new CauldronFeeWithdrawer(mim);
        withdrawer.setParameters(
            constants.getAddress("mainnet.aggregators.zeroXExchangProxy"),
            mimProvider,
            ICauldronFeeBridger(address(0))
        );
        withdrawer.setSwappingRecipient(constants.getAddress("mainnet.sSpell"), true);
        withdrawer.setOperator(constants.getAddress("mainnet.devOps.gelatoProxy"), true);
        withdrawer.setSwapTokenOut(IERC20(spell), true);
        withdrawer.setSwappingRecipient(sSpell, true);

        withdrawer.setBentoBox(IBentoBoxV1(constants.getAddress("mainnet.sushiBentoBox")), true);
        withdrawer.setBentoBox(IBentoBoxV1(constants.getAddress("mainnet.degenBox")), true);

        CauldronInfo[] memory cauldronInfos = constants.getCauldrons("mainnet", true);
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

        MSpellSender sender = new MSpellSender();
        sender.changePurchaser(0xdFE1a5b757523Ca6F7f049ac02151808E6A52111, constants.getAddress("mainnet.mimTreasury"), 50);
        sender.addMSpellRecipient(0xbD2fBaf2dc95bD78Cf1cD3c5235B33D1165E6797, 1, 1);
        sender.addMSpellRecipient(0xBd84472B31d947314fDFa2ea42460A2727F955Af, 43114, 106);
        sender.addMSpellRecipient(0x1DF188958A8674B5177f77667b8D173c3CdD9e51, 42161, 110);
        sender.addMSpellRecipient(0xa668762fb20bcd7148Db1bdb402ec06Eb6DAD569, 250, 112);

        sender.addReporter(hex"78a538cf4c73dba3794c0385d28758fed517cccf1440ecdfc61386a64116e58326bc7d6074e80815", 106);
        sender.addReporter(hex"20cb52832f35c61ccdbe5c336e405fe979de94301440ecdfc61386a64116e58326bc7d6074e80815", 110);
        sender.addReporter(hex"96bac90bee7f416d33601d1dc45efb19aca8ca621440ecdfc61386a64116e58326bc7d6074e80815", 112);

        sender.setWithdrawer(ICauldronFeeWithdrawer(address(withdrawer)));

        // Only when deploying live
        if (!testing) {
            withdrawer.transferOwnership(address(sender), true, false);
        }

        vm.stopBroadcast();
    }
}

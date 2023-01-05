// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "utils/BaseTest.sol";
import "script/GmxLens.s.sol";

contract GmxLensTest is BaseTest {
    GmxLens public lens;

    function setUp() public override {
        forkArbitrum(45611977);
        super.setUp();

        MyScript script = new MyScript();
        script.setTesting(true);
        (lens) = script.run();
    }

    function test() public {
        console2.log(lens.getTokenOutFromBurningGlp(constants.getAddress("arbitrum.usdc"), 30 ether));
    }
}

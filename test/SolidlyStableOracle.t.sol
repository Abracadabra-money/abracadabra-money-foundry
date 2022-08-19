// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "oracles/SolidlyStableOracle.sol";
import "utils/BaseTest.sol";
import "interfaces/IVelodromePairFactory.sol";
import "forge-std/console2.sol";

contract SolidlyStableOracleTest is BaseTest {
    struct Info {
        address pair;
        address oracleA;
        address oracleB;
    }

    Info[] pairs;

    function setUp() public override {
        super.setUp();

        pairs.push(
            Info({
                pair: 0xd16232ad60188B68076a235c65d692090caba155,
                oracleA: 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3, // usdc
                oracleB: 0x7f99817d87baD03ea21E05112Ca799d715730efe // susd
            })
        );

        pairs.push(
            Info({
                pair: 0x4F7ebc19844259386DBdDB7b2eB759eeFc6F8353,
                oracleA: 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3, // usdc
                oracleB: 0x8dBa75e83DA73cc766A7e5a0ee71F656BAb470d6 // dai
            })
        );
    }

    function test() public {
        // around a week span,
        uint256 samplePerDay = 1;
        uint256 steps = samplePerDay * 7;
        uint256 blockStart = 18919935;
        uint256 blockNo = 18919935;
        uint256 blockStep = (19784578 - blockStart) / steps;

        for (uint256 i = 0; i < pairs.length; i++) {
            blockNo = blockStart;
            console2.log(pairs[i].pair);

            uint256 totalAbsDiff = 0;
            for (uint256 j = 0; j < steps; j++) {
                console2.log("");
                console2.log("block", blockNo);

                forkOptimism(blockNo);
                totalAbsDiff += _testPair(ISolidlyPair(pairs[i].pair), IAggregator(pairs[i].oracleA), IAggregator(pairs[i].oracleB));
                blockNo += blockStep;
            }
            console2.log("");
            console.log("-> avg diff", totalAbsDiff / steps, "bips");
            console2.log("____");
            console2.log("");
        }
    }

    function _testPair(
        ISolidlyPair pair,
        IAggregator oracle0,
        IAggregator oracle1
    ) private returns (uint256 absDiff) {
        SolidlyStableOracle oracle = new SolidlyStableOracle(pair, oracle0, oracle1);
        uint256 feed = uint256(oracle.latestAnswer());
        uint256 realPrice = _poolLpPrice(pair, oracle0, oracle1);
        console2.log("fair price:", feed / 1e18);
        console2.log("real price:", realPrice / 1e18);

        if (feed > realPrice) {
            absDiff = ((feed - realPrice) * 10000) / realPrice;
            console2.log("+", absDiff, "bips");
        } else {
            absDiff = ((realPrice - feed) * 10000) / feed;
            console2.log("+", absDiff, "bips");
        }
    }

    function _poolLpPrice(
        ISolidlyPair pair,
        IAggregator oracle0,
        IAggregator oracle1
    ) private view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        (, int256 price0, , , ) = oracle0.latestRoundData();
        (, int256 price1, , , ) = oracle1.latestRoundData();
        uint256 normalizedReserve0 = reserve0 * (10**(18 - IStrictERC20(pair.token0()).decimals()));
        uint256 normalizedReserve1 = reserve1 * (10**(18 - IStrictERC20(pair.token1()).decimals()));
        uint256 normalizedPrice0 = uint256(price0) * (10**(18 - oracle0.decimals()));
        uint256 normalizedPrice1 = uint256(price1) * (10**(18 - oracle1.decimals()));

        return ((normalizedReserve0 * normalizedPrice0) + (normalizedReserve1 * normalizedPrice1)) / pair.totalSupply();
    }
}

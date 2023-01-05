// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "BoringSolidity/ERC20.sol";
import "oracles/UniswapLikeLPOracle.sol";
import "utils/VelodromeLib.sol";
import "utils/SolidlyLikeLib.sol";
import "utils/SolidlyUtils.sol";
import "utils/BaseTest.sol";
import "utils/SolidlyUtils.sol";
import "interfaces/ISolidlyLpWrapper.sol";
import "interfaces/ISolidlyRouter.sol";
import "interfaces/IOracle.sol";

contract SolidlyLpWrapperTest is BaseTest {
    address constant opWhale = 0x2A82Ae142b2e62Cb7D10b55E323ACB1Cab663a26;
    address constant usdcWhale = 0xAD7b4C162707E0B2b5f6fdDbD3f8538A5fbA0d60;

    ERC20 opToken;
    ERC20 usdcToken;
    ISolidlyPair underlyingLp;
    ISolidlyLpWrapper lp;
    ISolidlyRouter router;
    IOracle oracle;
    UniswapLikeLPOracle underlyingLpOracle;

    function setUp() public override {
        forkOptimism(18243290);
        super.setUp();
        
        underlyingLp = ISolidlyPair(constants.getAddress("optimism.velodrome.vOpUsdc"));

        lp = VelodromeLib.deployWrappedLp(
            underlyingLp,
            ISolidlyRouter(constants.getAddress("optimism.velodrome.router")),
            IVelodromePairFactory(constants.getAddress("optimism.velodrome.factory"))
        );
        lp.setFeeParameters(deployer, 10);
        lp.setStrategyExecutor(deployer, true);

        oracle = SolidlyLikeLib.deployVolatileLPOracle(
            "Abracadabra Velodrome vOP/USDC",
            lp,
            IAggregator(constants.getAddress("optimism.chainlink.op")),
            IAggregator(constants.getAddress("optimism.chainlink.usdc"))
        );

        router = ISolidlyRouter(constants.getAddress("optimism.velodrome.router"));
        opToken = ERC20(constants.getAddress("optimism.op"));
        usdcToken = ERC20(constants.getAddress("optimism.usdc"));

        underlyingLpOracle = UniswapLikeLPOracle(
            address(
                ERC20VaultAggregator(address(InverseOracle(address(ProxyOracle(address(oracle)).oracleImplementation())).oracle()))
                    .underlyingOracle()
            )
        );

        opToken.approve(address(router), type(uint256).max);
        usdcToken.approve(address(router), type(uint256).max);
        underlyingLp.approve(address(lp), type(uint256).max);
    }

    function testSolidlyLpWrapperMintBurnPrice() public {
        uint256 priceStart = oracle.peekSpot("");

        _mintLp(alice, 1_000_000 * 1e18, 1_500_000 * 1e6);
        _mintLp(carol, 1_000_000 * 1e18, 1_500_000 * 1e6);

        assertApproxEqAbs(priceStart, oracle.peekSpot(""), 6e7);

        vm.startPrank(alice);
        lp.leave(lp.balanceOf(alice));
        vm.stopPrank();

        _mintLp(bob, 500 * 1e18, 500 * 1e6);
        assertApproxEqAbs(priceStart, oracle.peekSpot(""), 6e7);

        vm.startPrank(carol);
        lp.leave(lp.balanceOf(carol) / 2);
        vm.stopPrank();

        assertApproxEqAbs(priceStart, oracle.peekSpot(""), 6e7);

        _mintLp(bob, 500_000 * 1e18, 500_000 * 1e6);
        assertApproxEqAbs(priceStart, oracle.peekSpot(""), 6e7);
    }

    function testSolidlyLpWrapperRewardHarvesting() public {
        uint256 initialPrice = oracle.peekSpot("");
        uint256 price = initialPrice;

        (, uint256 aliceLiquidity) = _mintLp(alice, 1_000_000 * 1e18, 1_500_000 * 1e6);
        (, uint256 carolLiquidity) = _mintLp(carol, 1_000_000 * 1e18, 1_500_000 * 1e6);

        _generateLpRewards();

        vm.prank(deployer);
        lp.harvest(0);

        // new price must be lower since it's the inverse price.
        assertLt(oracle.peekSpot(""), price);
        price = oracle.peekSpot("");

        vm.prank(alice);
        assertGt(lp.leaveAll(), aliceLiquidity);
        assertEq(oracle.peekSpot(""), price);

        vm.prank(carol);
        assertGt(lp.leaveAll(), carolLiquidity);
        assertApproxEqAbs(oracle.peekSpot(""), initialPrice, 6e7);
    }

    function _generateLpRewards() private {
        vm.prank(opWhale);
        opToken.transfer(address(this), 1_000_000 * 1e18);

        SolidlyUtils.simulateTrades(underlyingLp, opToken, opToken.balanceOf(address(this)), 99);
    }

    function _mintLp(
        address to,
        uint256 amountToken0,
        uint256 amountToken1
    ) private returns (uint256 shares, uint256 liquidity) {
        vm.prank(opWhale);
        opToken.transfer(address(this), amountToken0);
        vm.prank(usdcWhale);
        usdcToken.transfer(address(this), amountToken1);

        uint256 underlyingLpBefore = underlyingLp.balanceOf(address(this));
        uint256 lpBefore = lp.balanceOf(address(this));

        (, , liquidity) = router.addLiquidity(
            address(opToken),
            address(usdcToken),
            false,
            amountToken0,
            amountToken1,
            0,
            0,
            address(this),
            type(uint256).max
        );

        uint256 underlyingLpAfter = underlyingLp.balanceOf(address(this)) - underlyingLpBefore;
        uint256 lpBeforeEnter = lp.balanceOf(address(this));
        assertEq(underlyingLpAfter, liquidity);
        assertEq(lpBefore, lpBeforeEnter);

        shares = lp.enterFor(liquidity, to);

        assertEq(underlyingLp.balanceOf(address(this)) + liquidity, underlyingLpAfter);
        assertEq(lpBeforeEnter, lp.balanceOf(address(this)));
    }
}

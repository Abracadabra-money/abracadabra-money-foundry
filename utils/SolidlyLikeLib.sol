// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "BoringSolidity/interfaces/IERC20.sol";
import "oracles/ProxyOracle.sol";
import "oracles/TokenOracle.sol";
import "oracles/UniswapLikeLPOracle.sol";
import "oracles/InverseOracle.sol";
import "oracles/ERC20VaultAggregator.sol";
import "swappers/SolidlyLikeVolatileLPLevSwapper.sol";
import "swappers/SolidlyLikeVolatileLPSwapper.sol";
import "strategies/SolidlyGaugeVolatileLPStrategy.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/ISolidlyRouter.sol";
import "interfaces/ISwapperV2.sol";
import "interfaces/ILevSwapperV2.sol";
import "interfaces/ISolidlyLpWrapper.sol";

library SolidlyLikeLib {
    function deployVolatileZeroExSwappers(
        IBentoBoxV1 degenBox,
        ISolidlyRouter router,
        ISolidlyLpWrapper collateral,
        IERC20 mim,
        address zeroXExchangeProxy
    ) internal returns (ISwapperV2 swapper, ILevSwapperV2 levSwapper) {
        swapper = ISwapperV2(address(new SolidlyLikeVolatileLPSwapper(degenBox, collateral, mim, zeroXExchangeProxy)));
        levSwapper = ILevSwapperV2(
            address(new SolidlyLikeVolatileLPLevSwapper(degenBox, router, collateral, mim, zeroXExchangeProxy))
        );
    }

    function deployVolatileLPStrategy(
        SolidlyLpWrapper collateral,
        IBentoBoxV1 degenBox,
        ISolidlyRouter router,
        ISolidlyGauge gauge,
        address reward,
        bytes32 initHash,
        bool usePairToken0
    ) internal returns (SolidlyGaugeVolatileLPStrategy strategy) {
        strategy = new SolidlyGaugeVolatileLPStrategy(collateral, degenBox, router, gauge, reward, initHash, usePairToken0);
    }

    function deployVolatileLPOracle(
        string memory desc,
        ISolidlyLpWrapper wrapper,
        IAggregator tokenAOracle,
        IAggregator tokenBOracle
    ) internal returns (ProxyOracle proxy) {
        IUniswapV2Pair lp = IUniswapV2Pair(address(wrapper.underlying()));
        proxy = new ProxyOracle();
        TokenOracle tokenOracle = new TokenOracle(tokenAOracle, tokenBOracle);
        UniswapLikeLPOracle lpOracle = new UniswapLikeLPOracle(lp, tokenOracle);
        ERC20VaultAggregator vaultAggregator = new ERC20VaultAggregator(wrapper, lpOracle);
        InverseOracle invertedOracle = new InverseOracle(vaultAggregator, tokenBOracle, desc);
        proxy.changeOracleImplementation(invertedOracle);
    }
}

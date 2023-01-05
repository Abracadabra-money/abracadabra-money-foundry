// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "swappers/UniswapLikeLPLevSwapper.sol";
import "swappers/UniswapLikeLPSwapper.sol";
import "oracles/ProxyOracle.sol";
import "oracles/TokenOracle.sol";
import "oracles/UniswapLikeLPOracle.sol";
import "oracles/InverseOracle.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/IUniswapV2Pair.sol";
import "interfaces/IUniswapV2Router01.sol";
import "interfaces/ISwapperV2.sol";
import "interfaces/ILevSwapperV2.sol";

library UniswapLikeLib {
    function deployZeroExSwappers(
        IBentoBoxV1 degenBox,
        IUniswapV2Router01 uniswapLikeRouter,
        IUniswapV2Pair collateral,
        IERC20 mim,
        address zeroXExchangeProxy
    ) internal returns (ISwapperV2 swapper, ILevSwapperV2 levSwapper) {
        swapper = ISwapperV2(address(new UniswapLikeLPSwapper(degenBox, collateral, mim, zeroXExchangeProxy)));
        levSwapper = ILevSwapperV2(
            address(new UniswapLikeLPLevSwapper(degenBox, uniswapLikeRouter, collateral, mim, zeroXExchangeProxy))
        );
    }

    function deployLPOracle(
        string memory desc,
        IUniswapV2Pair lp,
        IAggregator tokenAOracle,
        IAggregator tokenBOracle
    ) internal returns (ProxyOracle proxy) {
        proxy = new ProxyOracle();
        TokenOracle tokenOracle = new TokenOracle(tokenAOracle, tokenBOracle);
        UniswapLikeLPOracle lpOracle = new UniswapLikeLPOracle(lp, tokenOracle);
        InverseOracle invertedOracle = new InverseOracle(IAggregator(lpOracle), tokenBOracle, desc);
        proxy.changeOracleImplementation(invertedOracle);
    }
}

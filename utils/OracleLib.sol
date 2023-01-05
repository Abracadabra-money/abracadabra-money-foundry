// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "BoringSolidity/interfaces/IERC20.sol";
import "oracles/ProxyOracle.sol";
import "oracles/TokenOracle.sol";
import "oracles/InverseOracle.sol";

library OracleLib {
    function deploySimpleInvertedOracle(string memory desc, IAggregator aggregator) internal returns (ProxyOracle proxy) {
        proxy = new ProxyOracle();
        InverseOracle invertedOracle = new InverseOracle(aggregator, IAggregator(address(0)), desc);
        proxy.changeOracleImplementation(invertedOracle);
    }

    function deploySimpleInvertedOracle(
        string memory desc,
        IAggregator aggregator,
        IAggregator denominator
    ) internal returns (ProxyOracle proxy) {
        proxy = new ProxyOracle();
        InverseOracle invertedOracle = new InverseOracle(aggregator, denominator, desc);
        proxy.changeOracleImplementation(invertedOracle);
    }

    function deploySimpleProxyOracle(
        IOracle oracle
    ) internal returns (ProxyOracle proxy) {
        proxy = new ProxyOracle();
        proxy.changeOracleImplementation(oracle);
    }
}

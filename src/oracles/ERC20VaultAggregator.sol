// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "interfaces/IERC20Vault.sol";
import "interfaces/IAggregator.sol";

contract ERC20VaultAggregator is IAggregator {
    uint8 public immutable decimals;
    IERC20Vault public immutable vault;

    /// @notice price of the underlying vault token
    IAggregator public immutable underlyingOracle;

    constructor(IERC20Vault _vault, IAggregator _underlyingOracle) {
        vault = _vault;
        underlyingOracle = _underlyingOracle;
        decimals = _underlyingOracle.decimals();
    }

    function latestAnswer() public view override returns (int256) {
        return int256(vault.toAmount(uint256(underlyingOracle.latestAnswer())));
    }

    function latestRoundData()
        external
        view
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        return (0, latestAnswer(), 0, 0, 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/interfaces/IERC20.sol";
import "libraries/SafeApprove.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/IERC4626.sol";

/// @notice Wrap token to ERC4626 Tokenized Vault and deposit into DegenBox for recipient
/// Need to be used atomically, do not transfer fund in it and then wrap / unwrap on another block as
/// it could be retrieved by anyone else, by calling deposit or withdraw.
contract DegenBoxERC4626Wrapper {
    using SafeApprove for IERC20;

    IBentoBoxV1 immutable degenBox;
    IERC4626 immutable wrapper;
    IERC20 immutable underlying;

    constructor(IBentoBoxV1 _degenBox, IERC4626 _wrapper) {
        degenBox = _degenBox;
        wrapper = _wrapper;

        IERC20 _underlying = wrapper.asset();
        _underlying.approve(address(wrapper), type(uint256).max);

        underlying = _underlying;
    }

    function wrap(address recipient, uint256 amount) external returns (uint256 amountOut, uint256 shareOut) {
        wrapper.deposit(amount, address(degenBox));
        return degenBox.deposit(IERC20(address(wrapper)), address(degenBox), recipient, amount, 0);
    }

    function unwrap(address recipient, uint256 amount) external returns (uint256 amountOut, uint256 shareOut) {
        wrapper.withdraw(amount, address(degenBox), address(this));
        return degenBox.deposit(underlying, address(degenBox), recipient, amount, 0);
    }
}

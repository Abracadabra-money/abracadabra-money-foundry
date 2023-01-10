// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/BoringOwnable.sol";
import "BoringSolidity/libraries/BoringERC20.sol";
import "BoringSolidity/ERC20.sol";
import "interfaces/ICauldronFeeBridger.sol";
import "interfaces/IAnyswapRouter.sol";
import "libraries/SafeApprove.sol";

contract AnyswapCauldronFeeBridger is BoringOwnable, ICauldronFeeBridger {
    using BoringERC20 for IERC20;
    using SafeApprove for IERC20;

    event LogAuthorizedCallerChanged(address indexed caller, bool previous, bool current);
    event LogParametersChanged(IAnyswapRouter indexed anyswapRouter, address indexed recipient, uint256 chainId);

    error ErrUnauthorizedCaller(address caller);

    IAnyswapRouter public anyswapRouter;
    address public recipient;
    uint256 public recipientChainId;

    mapping(address => bool) authorizedCallers;

    modifier onlyAuthorizedCallers() {
        if (!authorizedCallers[msg.sender]) {
            revert ErrUnauthorizedCaller(msg.sender);
        }
        _;
    }

    constructor(
        IAnyswapRouter _anyswapRouter,
        address _recipient,
        uint256 _recipientChainId
    ) {
        anyswapRouter = _anyswapRouter;
        recipient = _recipient;
        recipientChainId = _recipientChainId;
    }

    function bridge(IERC20 token, uint256 amount) external onlyAuthorizedCallers {
        token.safeApprove(address(anyswapRouter), amount);
        anyswapRouter.anySwapOut(address(token), recipient, amount, recipientChainId);
        token.safeApprove(address(anyswapRouter), 0);
    }

    function setParameters(
        IAnyswapRouter _anyswapRouter,
        address _recipient,
        uint256 _recipientChainId
    ) external onlyOwner {
        anyswapRouter = _anyswapRouter;
        recipient = _recipient;
        recipientChainId = _recipientChainId;
        emit LogParametersChanged(_anyswapRouter, _recipient, _recipientChainId);
    }

    function setAuthorizedCaller(address caller, bool enabled) external onlyOwner {
        emit LogAuthorizedCallerChanged(caller, authorizedCallers[caller], enabled);
        authorizedCallers[caller] = enabled;
    }
}

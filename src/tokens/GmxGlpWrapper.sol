// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/libraries/BoringERC20.sol";
import "BoringSolidity/BoringOwnable.sol";
import "tokens/ERC20WithPreApprove.sol";
import "OpenZeppelin/utils/Address.sol";
import "forge-std/console2.sol";

abstract contract GmxGlpWrapperData is BoringOwnable, ERC20WithPreApprove {
    error ErrNotStrategyExecutor(address);

    IERC20 public sGlp;
    string public name;
    string public symbol;
    address public rewardHandler;
    mapping(address => bool) public strategyExecutors;

    modifier onlyStrategyExecutor() {
        if (msg.sender != owner && !strategyExecutors[msg.sender]) {
            revert ErrNotStrategyExecutor(msg.sender);
        }
        _;
    }
}

contract GmxGlpWrapper is GmxGlpWrapperData {
    using BoringERC20 for IERC20;

    event LogRewardHandlerChanged(address indexed previous, address indexed current);
    event LogStrategyExecutorChanged(address indexed executor, bool allowed);
    event LogStakedGlpChanged(IERC20 indexed previous, IERC20 indexed current);

    address private immutable _preApprovedContract;

    constructor(
        IERC20 _sGlp,
        string memory _name,
        string memory _symbol,
        address __preApprovedContract
    ) {
        name = _name;
        symbol = _symbol;
        sGlp = _sGlp;
        _preApprovedContract = __preApprovedContract;
    }

    function decimals() external view returns (uint8) {
        return sGlp.safeDecimals();
    }

    function preApprovedContract() public override view returns(address) {
        return _preApprovedContract;
    }

    function _wrap(uint256 amount, address recipient) internal {
        _mint(recipient, amount);
        sGlp.safeTransferFrom(msg.sender, address(this), amount);
    }

    function _unwrap(uint256 amount, address recipient) internal {
        _burn(msg.sender, amount);
        sGlp.safeTransfer(recipient, amount);
    }

    function wrap(uint256 amount) external {
        _wrap(amount, msg.sender);
    }

    function wrapFor(uint256 amount, address recipient) external {
        _wrap(amount, recipient);
    }

    function unwrap(uint256 amount) external {
        _unwrap(amount, msg.sender);
    }

    function unwrapTO(uint256 amount, address recipient) external {
        _unwrap(amount, recipient);
    }

    function unwrapAll() external {
        _unwrap(balanceOf[msg.sender], msg.sender);
    }

    function unwrapAllTo(address recipient) external {
        _unwrap(balanceOf[msg.sender], recipient);
    }

    function setStrategyExecutor(address executor, bool value) external onlyOwner {
        strategyExecutors[executor] = value;
        emit LogStrategyExecutorChanged(executor, value);
    }

    function setRewardHandler(address _rewardHandler) external onlyOwner {
        emit LogRewardHandlerChanged(rewardHandler, _rewardHandler);
        rewardHandler = _rewardHandler;
    }

    function setStakedGlp(IERC20 _sGlp) external onlyOwner {
        emit LogStakedGlpChanged(sGlp, _sGlp);
        sGlp = _sGlp;
    }

    // Forward unknown function calls to the reward handler.
    fallback() external {
        _delegate(rewardHandler);
    }

    /**
     * From https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/Proxy.sol
     *
     * @dev Delegates the current call to `implementation`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     */
    function _delegate(address implementation) private {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}

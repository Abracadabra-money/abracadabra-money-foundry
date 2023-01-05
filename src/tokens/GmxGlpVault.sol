// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "BoringSolidity/BoringOwnable.sol";
import "./ERC4626.sol";

contract GmxGlpVaultData is ERC4626, BoringOwnable {
    error ErrNotStrategyExecutor(address);

    address public rewardHandler;
    mapping(address => bool) public strategyExecutors;

    modifier onlyStrategyExecutor() {
        if (msg.sender != owner && !strategyExecutors[msg.sender]) {
            revert ErrNotStrategyExecutor(msg.sender);
        }
        _;
    }
}

/// @dev Vault version of the GLP Wrapper, auto compound yield increase shares value
contract GmxGlpVault is GmxGlpVaultData {
    event LogRewardHandlerChanged(address indexed previous, address indexed current);
    event LogStrategyExecutorChanged(address indexed executor, bool allowed);
    event LogStakedGlpChanged(ERC20 indexed previous, ERC20 indexed current);

    constructor(
        ERC20 __asset,
        string memory _name,
        string memory _symbol
    ) {
        _asset = __asset;
        name = _name;
        symbol = _symbol;
    }

    function setStrategyExecutor(address executor, bool value) external onlyOwner {
        strategyExecutors[executor] = value;
        emit LogStrategyExecutorChanged(executor, value);
    }

    function setRewardHandler(address _rewardHandler) external onlyOwner {
        emit LogRewardHandlerChanged(rewardHandler, _rewardHandler);
        rewardHandler = _rewardHandler;
    }

    function setStakedGlp(ERC20 _sGlp) external onlyOwner {
        emit LogStakedGlpChanged(_asset, _sGlp);
        _asset = _sGlp;
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

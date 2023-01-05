// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20, ERC20WithSupply} from "BoringSolidity/ERC20.sol";
import {BoringERC20} from "BoringSolidity/libraries/BoringERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "interfaces/IERC4626.sol";

/// @notice Adapted from Solmate ERC4626
/// @notice Minimal ERC4626 tokenized Vault implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/mixins/ERC4626.sol)
contract ERC4626 is IERC4626, ERC20WithSupply {
    using BoringERC20 for ERC20;
    using FixedPointMathLib for uint256;

    error ErrZeroShares();

    string public name;
    string public symbol;
    ERC20 public _asset;

    function asset() external view returns (IERC20) {
        return _asset;
    }

    function decimals() external view returns (uint8) {
        return _asset.safeDecimals();
    }

    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        if ((shares = previewDeposit(assets)) == 0) {
            revert ErrZeroShares();
        }

        // Need to transfer before minting or ERC777s could reenter.
        _asset.transferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        _asset.transferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares;
            }
        }

        _burn(owner, shares);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        _asset.transfer(receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.
            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares;
            }
        }

        // Check for rounding error since we round down in previewRedeem.
        if ((assets = previewRedeem(shares)) == 0) {
            revert ErrZeroShares();
        }

        _burn(owner, shares);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        _asset.transfer(receiver, assets);
    }

    function totalAssets() public view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return convertToAssets(balanceOf[owner]);
    }

    function maxRedeem(address owner) public view virtual returns (uint256) {
        return balanceOf[owner];
    }
}

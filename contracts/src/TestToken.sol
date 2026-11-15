// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ERC20 } from "solady/tokens/ERC20.sol";

/// @title TestToken
/// @notice Testnet-only ERC20 (tWETH 18 dec, tUSDC 6 dec). Anyone may mint, up to `mintCap` per call.
/// @dev Deployed with CREATE2 through the deterministic deployer with the same salt and constructor args on
///      Base Sepolia and Unichain Sepolia, so each token has the same address (and pools the same token0/token1
///      order) on both chains. Changing this file changes the init code and therefore the addresses.
contract TestToken is ERC20 {
    error MintCapExceeded(uint256 amount, uint256 cap);

    uint8 private immutable _DECIMALS;
    uint256 public immutable mintCap;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 mintCap_) {
        _name = name_;
        _symbol = symbol_;
        _DECIMALS = decimals_;
        mintCap = mintCap_;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }

    /// @notice Mint `amount` to `to`. Reverts above `mintCap` per call.
    function mint(address to, uint256 amount) external {
        if (amount > mintCap) revert MintCapExceeded(amount, mintCap);
        _mint(to, amount);
    }
}

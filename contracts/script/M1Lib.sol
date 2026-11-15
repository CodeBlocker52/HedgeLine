// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PoolKey } from "v4-core/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "v4-core/types/PoolId.sol";
import { Currency } from "v4-core/types/Currency.sol";
import { IHooks } from "v4-core/interfaces/IHooks.sol";
import { FullMath } from "v4-core/libraries/FullMath.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import { TestToken } from "../src/TestToken.sol";

/// @notice Shared M1 constants and helpers (deploy script + tests).
library M1Lib {
    /// Deterministic deployer (Arachnid), present on Base Sepolia and Unichain Sepolia (M0 review, `cast code`).
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// CREATE2 salts. Same salt + same init code on both chains => same address on both chains.
    /// tWETH salt mined (contracts/script/MineTokenSalt.s.sol) so that address(tWETH) < address(tUSDC): tWETH is token0.
    bytes32 internal constant SALT_TWETH = keccak256("hedgeline.TestToken.tWETH.v1.0");
    bytes32 internal constant SALT_TUSDC = keccak256("hedgeline.TestToken.tUSDC.v1");
    bytes32 internal constant SALT_PING_ORIGIN = keccak256("hedgeline.spike.PingOrigin.m1");

    /// Reference pool: no hook, 0.30% fee, tick spacing 60, ~3000 tUSDC per tWETH.
    uint24 internal constant FEE = 3000;
    int24 internal constant TICK_SPACING = 60;
    uint256 internal constant USDC_PER_WETH = 3000;

    /// Full-range liquidity. L = 5e14 at 3000 USDC/ETH ≈ 9.13 tWETH + 27,386 tUSDC.
    uint128 internal constant LIQUIDITY = 5e14;

    function tWethInitCode() internal pure returns (bytes memory) {
        return abi.encodePacked(
            type(TestToken).creationCode, abi.encode("Hedgeline Test WETH", "tWETH", uint8(18), uint256(1_000e18))
        );
    }

    function tUsdcInitCode() internal pure returns (bytes memory) {
        return abi.encodePacked(
            type(TestToken).creationCode, abi.encode("Hedgeline Test USDC", "tUSDC", uint8(6), uint256(10_000_000e6))
        );
    }

    function create2Address(bytes32 salt, bytes memory initCode) internal pure returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, salt, keccak256(initCode)))))
        );
    }

    function poolKey(address tWeth, address tUsdc) internal pure returns (PoolKey memory key) {
        (address c0, address c1) = tWeth < tUsdc ? (tWeth, tUsdc) : (tUsdc, tWeth);
        key = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });
    }

    function poolId(address tWeth, address tUsdc) internal pure returns (bytes32) {
        return PoolId.unwrap(PoolIdLibrary.toId(poolKey(tWeth, tUsdc)));
    }

    /// sqrtPriceX96 for USDC_PER_WETH, with decimals (tWETH 18, tUSDC 6) and token order applied.
    /// price = token1 raw units per token0 raw unit; sqrtPriceX96 = sqrt(price · 2^192).
    function initialSqrtPriceX96(bool wethIsToken0) internal pure returns (uint160) {
        (uint256 num, uint256 den) =
            wethIsToken0 ? (USDC_PER_WETH * 1e6, uint256(1e18)) : (uint256(1e18), USDC_PER_WETH * 1e6);
        return uint160(FixedPointMathLib.sqrt(FullMath.mulDiv(num, 1 << 192, den)));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console2 } from "forge-std/Script.sol";
import { M1Lib } from "./M1Lib.sol";

/// @notice Offline salt miner (no RPC, no tx). Keeps the tUSDC salt fixed and iterates
///         keccak256("hedgeline.TestToken.tWETH.v1.<i>") until address(tWETH) < address(tUSDC), so tWETH is token0.
/// Usage: forge script contracts/script/MineTokenSalt.s.sol
contract MineTokenSalt is Script {
    function run() external pure {
        address usdc = M1Lib.create2Address(M1Lib.SALT_TUSDC, M1Lib.tUsdcInitCode());
        bytes32 wethCodeHash = keccak256(M1Lib.tWethInitCode());
        for (uint256 i; i < 10_000; ++i) {
            string memory label = string.concat("hedgeline.TestToken.tWETH.v1.", vm.toString(i));
            bytes32 salt = keccak256(bytes(label));
            address weth = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), M1Lib.CREATE2_DEPLOYER, salt, wethCodeHash))))
            );
            if (weth < usdc) {
                console2.log("label", label);
                console2.log("salt");
                console2.logBytes32(salt);
                console2.log("tWETH", weth);
                console2.log("tUSDC", usdc);
                return;
            }
        }
        revert("no salt found");
    }
}

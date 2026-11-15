// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { TestToken } from "../../src/TestToken.sol";
import { M1Lib } from "../../script/M1Lib.sol";

contract TestTokenTest is Test {
    function test_metadataAndMintCap() public {
        TestToken t = new TestToken("Hedgeline Test USDC", "tUSDC", 6, 10_000_000e6);
        assertEq(t.name(), "Hedgeline Test USDC");
        assertEq(t.symbol(), "tUSDC");
        assertEq(t.decimals(), 6);
        t.mint(address(this), 10_000_000e6);
        assertEq(t.balanceOf(address(this)), 10_000_000e6);
        vm.expectRevert(abi.encodeWithSelector(TestToken.MintCapExceeded.selector, 10_000_000e6 + 1, 10_000_000e6));
        t.mint(address(this), 10_000_000e6 + 1);
    }

    /// CREATE2 through the deterministic deployer gives the same address regardless of chain id or sender nonce.
    function test_create2AddressIsChainIndependent() public {
        vm.etch(
            M1Lib.CREATE2_DEPLOYER,
            hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"
        );
        address predicted = M1Lib.create2Address(M1Lib.SALT_TWETH, M1Lib.tWethInitCode());
        for (uint256 i; i < 2; ++i) {
            uint256 snap = vm.snapshotState();
            vm.chainId(i == 0 ? 84532 : 1301);
            vm.setNonce(address(this), uint64(7 + i * 5));
            (bool ok, bytes memory ret) =
                M1Lib.CREATE2_DEPLOYER.call(abi.encodePacked(M1Lib.SALT_TWETH, M1Lib.tWethInitCode()));
            assertTrue(ok);
            assertEq(address(bytes20(ret)), predicted);
            assertEq(TestToken(predicted).decimals(), 18);
            assertEq(TestToken(predicted).symbol(), "tWETH");
            vm.revertToState(snap);
        }
    }

    /// sqrtPriceX96 encodes ~3000 tUSDC per tWETH in either token order.
    function test_initialSqrtPriceBothOrders() public pure {
        uint256 q192 = 1 << 192;
        // tWETH token0: price = token1/token0 raw = 3000e6 / 1e18
        uint256 p0 = M1Lib.initialSqrtPriceX96(true);
        assertApproxEqRel(p0 * p0 * 1e18 / q192, 3000e6, 1e12); // tUSDC raw per 1e18 tWETH raw
        // tUSDC token0: price = 1e18 / 3000e6; invert
        uint256 p1 = M1Lib.initialSqrtPriceX96(false);
        uint256 rawWethPerUsdc = p1 * p1 / q192; // 1e18/3000e6 ≈ 333,333,333
        assertApproxEqRel(rawWethPerUsdc, 333_333_333, 1e12);
    }
}

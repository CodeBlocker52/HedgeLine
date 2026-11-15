// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console2 } from "forge-std/Script.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { PoolId } from "v4-core/types/PoolId.sol";
import { Currency } from "v4-core/types/Currency.sol";
import { ModifyLiquidityParams } from "v4-core/types/PoolOperation.sol";
import { StateLibrary } from "v4-core/libraries/StateLibrary.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";

import { TestToken } from "../src/TestToken.sol";
import { PingOrigin } from "../src/spike/PingOrigin.sol";
import { PingReactive } from "../src/spike/PingReactive.sol";
import { PingReceiver } from "../src/spike/PingReceiver.sol";
import { M1Lib } from "./M1Lib.sol";

interface IPoolModifyLiquidityTest {
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes memory hookData)
        external
        payable
        returns (int256 delta);
}

interface ICallbackProxy {
    function depositTo(address contract_) external payable;
    function reserves(address contract_) external view returns (uint256);
    function debt(address contract_) external view returns (uint256);
}

/// @title M1Deploy
/// @notice All M1 deployments across Base Sepolia, Unichain Sepolia and Lasna, in Reactive's documented order.
///   Base:     PingOrigin (CREATE2), tWETH/tUSDC (CREATE2), mint, init no-hook pool at 3000 tUSDC/tWETH, full-range liquidity,
///             approve PoolSwapTest
///   Unichain: PingOrigin + tWETH/tUSDC with the same salts; asserts identical addresses + token order
///   Lasna:    PingReactive{1 lREACT}
///   Base:     PingReceiver(proxy, reactive) + depositTo(proxy, 0.003 ETH)
///   Lasna:    setReceiver
/// Every step is idempotent (skips what already exists), so a re-run after a partial failure is safe.
/// Dry run:  forge script contracts/script/M1Deploy.s.sol --multi
/// Deploy:   forge script contracts/script/M1Deploy.s.sol --multi --broadcast --slow
/// Addresses are written to scripts/deployments.json only when broadcasting.
contract M1Deploy is Script {
    using StateLibrary for IPoolManager;

    string internal constant REG = "scripts/deployments.json";

    // FACTS.md §2.2 / §2.3
    address internal constant BASE_POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address internal constant BASE_CALLBACK_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
    address internal constant BASE_POOL_SWAP_TEST = 0x8B5bcC363ddE2614281aD875bad385E0A785D3B9;
    address internal constant BASE_POOL_MODIFY_LIQUIDITY_TEST = 0x37429cD17Cb1454C34E7F50b09725202Fd533039;

    uint256 internal constant REACTIVE_FUNDING = 1 ether; // lREACT
    uint256 internal constant RECEIVER_DEPOSIT = 0.003 ether; // Base Sepolia ETH, callback fees
    uint64 internal constant CALLBACK_GAS_LIMIT = 300_000;
    uint256 internal constant MINT_TWETH = 100e18;
    uint256 internal constant MINT_TUSDC = 1_000_000e6;

    uint256 internal pk;
    address internal deployer;
    bool internal broadcasting;
    uint256 internal baseFork;
    uint256 internal lasnaFork;

    address internal pingOrigin;
    address internal tWeth;
    address internal tUsdc;
    bytes32 internal poolId;
    address internal reactive;
    address internal receiver;

    function run() external {
        pk = _privateKey();
        deployer = vm.addr(pk);
        broadcasting = vm.isContext(VmSafe.ForgeContext.ScriptBroadcast);
        console2.log("deployer", deployer);
        console2.log("broadcasting", broadcasting);

        _base1();
        _unichain();
        _lasnaDeploy();
        _base2();
        _lasnaWire();

        console2.log("== M1 summary ==");
        console2.log("PingOrigin (Base + Unichain)", pingOrigin);
        console2.log("tWETH (Base + Unichain)", tWeth);
        console2.log("tUSDC (Base + Unichain)", tUsdc);
        console2.log("poolId");
        console2.logBytes32(poolId);
        console2.log("PingReactive (Lasna)", reactive);
        console2.log("PingReceiver (Base)", receiver);
    }

    // ─────────────────────────── Base Sepolia, part 1 ───────────────────────────

    function _base1() internal {
        baseFork = vm.createSelectFork("base_sepolia");
        require(block.chainid == 84532, "not Base Sepolia");
        _requireDeployer();
        vm.startBroadcast(pk);

        pingOrigin = _create2PingOrigin();
        tWeth = _create2Token(M1Lib.SALT_TWETH, M1Lib.tWethInitCode());
        tUsdc = _create2Token(M1Lib.SALT_TUSDC, M1Lib.tUsdcInitCode());
        require(TestToken(tWeth).decimals() == 18 && TestToken(tUsdc).decimals() == 6, "decimals");
        require(tWeth < tUsdc, "tWETH must be token0 (plan.md 3.2)");

        if (TestToken(tWeth).balanceOf(deployer) < MINT_TWETH / 2) TestToken(tWeth).mint(deployer, MINT_TWETH);
        if (TestToken(tUsdc).balanceOf(deployer) < MINT_TUSDC / 2) TestToken(tUsdc).mint(deployer, MINT_TUSDC);

        IPoolManager pm = IPoolManager(BASE_POOL_MANAGER);
        PoolKey memory key = M1Lib.poolKey(tWeth, tUsdc);
        poolId = M1Lib.poolId(tWeth, tUsdc);
        (uint160 sqrtP,,,) = pm.getSlot0(PoolId.wrap(poolId));
        if (sqrtP == 0) pm.initialize(key, M1Lib.initialSqrtPriceX96(tWeth < tUsdc));

        if (pm.getLiquidity(PoolId.wrap(poolId)) == 0) {
            _approve(tWeth, BASE_POOL_MODIFY_LIQUIDITY_TEST);
            _approve(tUsdc, BASE_POOL_MODIFY_LIQUIDITY_TEST);
            IPoolModifyLiquidityTest(BASE_POOL_MODIFY_LIQUIDITY_TEST)
                .modifyLiquidity(
                    key,
                    ModifyLiquidityParams({
                        tickLower: TickMath.minUsableTick(M1Lib.TICK_SPACING),
                        tickUpper: TickMath.maxUsableTick(M1Lib.TICK_SPACING),
                        liquidityDelta: int256(uint256(M1Lib.LIQUIDITY)),
                        salt: 0
                    }),
                    ""
                );
        }
        _approve(tWeth, BASE_POOL_SWAP_TEST);
        _approve(tUsdc, BASE_POOL_SWAP_TEST);
        vm.stopBroadcast();

        (sqrtP,,,) = pm.getSlot0(PoolId.wrap(poolId));
        console2.log("Base pool sqrtPriceX96", sqrtP);
        console2.log("Base pool liquidity", pm.getLiquidity(PoolId.wrap(poolId)));
        console2.log("tWETH is token0", tWeth < tUsdc);

        _record("baseSepolia", "PingOrigin", pingOrigin);
        _record("baseSepolia", "tWETH", tWeth);
        _record("baseSepolia", "tUSDC", tUsdc);
        _recordString("baseSepolia", "referencePoolId", vm.toString(poolId));
        _recordString(
            "baseSepolia",
            "referencePoolKey",
            string.concat("fee=3000,tickSpacing=60,hooks=0x0,currency0=", vm.toString(Currency.unwrap(key.currency0)))
        );
    }

    // ─────────────────────────── Unichain Sepolia ───────────────────────────

    function _unichain() internal {
        vm.createSelectFork("unichain_sepolia");
        require(block.chainid == 1301, "not Unichain Sepolia");
        _requireDeployer();
        vm.startBroadcast(pk);
        address po = _create2PingOrigin();
        address w = _create2Token(M1Lib.SALT_TWETH, M1Lib.tWethInitCode());
        address u = _create2Token(M1Lib.SALT_TUSDC, M1Lib.tUsdcInitCode());
        vm.stopBroadcast();

        // plan.md §3.2: identical addresses and token0/token1 order on both chains, revert otherwise.
        require(po == pingOrigin, "PingOrigin address differs across chains");
        require(w == tWeth, "tWETH address differs across chains");
        require(u == tUsdc, "tUSDC address differs across chains");
        require((w < u) == (tWeth < tUsdc), "token order differs across chains");
        require(TestToken(w).decimals() == 18 && TestToken(u).decimals() == 6, "decimals");

        _record("unichainSepolia", "PingOrigin", po);
        _record("unichainSepolia", "tWETH", w);
        _record("unichainSepolia", "tUSDC", u);
    }

    // ─────────────────────────── Lasna ───────────────────────────

    function _lasnaDeploy() internal {
        lasnaFork = vm.createSelectFork("lasna");
        require(block.chainid == 5318007, "not Lasna");
        _requireDeployer();
        reactive = _recorded("lasna", "PingReactive");
        if (reactive != address(0)) {
            require(PingReactive(payable(reactive)).poolId() == uint256(poolId), "recorded PingReactive: other pool");
            console2.log("PingReactive already deployed", reactive);
            return;
        }
        vm.startBroadcast(pk);
        reactive = address(
            new PingReactive{ value: REACTIVE_FUNDING }(
                pingOrigin, pingOrigin, BASE_POOL_MANAGER, poolId, CALLBACK_GAS_LIMIT
            )
        );
        vm.stopBroadcast();
        _record("lasna", "PingReactive", reactive);
    }

    // ─────────────────────────── Base Sepolia, part 2 ───────────────────────────

    function _base2() internal {
        vm.selectFork(baseFork);
        require(block.chainid == 84532, "not Base Sepolia");
        receiver = _recorded("baseSepolia", "PingReceiver");
        vm.startBroadcast(pk);
        if (receiver == address(0)) {
            receiver = address(new PingReceiver(IPayable(payable(BASE_CALLBACK_PROXY)), reactive));
        }
        require(PingReceiver(payable(receiver))._CALLBACK_SENDER() == reactive, "receiver bound to other reactive");
        uint256 have = ICallbackProxy(BASE_CALLBACK_PROXY).reserves(receiver);
        if (have < RECEIVER_DEPOSIT) {
            ICallbackProxy(BASE_CALLBACK_PROXY).depositTo{ value: RECEIVER_DEPOSIT - have }(receiver);
        }
        vm.stopBroadcast();
        console2.log("receiver proxy reserves (wei)", ICallbackProxy(BASE_CALLBACK_PROXY).reserves(receiver));
        _record("baseSepolia", "PingReceiver", receiver);
    }

    function _lasnaWire() internal {
        vm.selectFork(lasnaFork);
        require(block.chainid == 5318007, "not Lasna");
        if (PingReactive(payable(reactive)).receiver() == receiver) return;
        vm.startBroadcast(pk);
        PingReactive(payable(reactive)).setReceiver(receiver);
        vm.stopBroadcast();
    }

    // ─────────────────────────── helpers ───────────────────────────

    function _create2PingOrigin() internal returns (address a) {
        address predicted = M1Lib.create2Address(M1Lib.SALT_PING_ORIGIN, type(PingOrigin).creationCode);
        if (predicted.code.length == 0) {
            a = address(new PingOrigin{ salt: M1Lib.SALT_PING_ORIGIN }());
            require(a == predicted, "PingOrigin CREATE2 mismatch");
        }
        return predicted;
    }

    function _create2Token(bytes32 salt, bytes memory initCode) internal returns (address predicted) {
        predicted = M1Lib.create2Address(salt, initCode);
        if (predicted.code.length == 0) {
            (bool ok, bytes memory ret) = M1Lib.CREATE2_DEPLOYER.call(abi.encodePacked(salt, initCode));
            require(ok && address(bytes20(ret)) == predicted, "token CREATE2 failed");
        }
    }

    function _approve(address token, address spender) internal {
        if (TestToken(token).allowance(deployer, spender) < type(uint128).max) {
            TestToken(token).approve(spender, type(uint256).max);
        }
    }

    function _requireDeployer() internal view {
        string memory expected = vm.envOr("DEPLOYER_ADDRESS", string(""));
        if (bytes(expected).length != 0) {
            require(vm.parseAddress(expected) == deployer, "PRIVATE_KEY != DEPLOYER_ADDRESS");
        }
    }

    /// Parses PRIVATE_KEY without ever putting its value into an error message (forge parse errors echo input).
    function _privateKey() internal view returns (uint256 k) {
        bytes memory b = bytes(vm.envString("PRIVATE_KEY"));
        uint256 start = (b.length >= 2 && b[0] == "0" && (b[1] == "x" || b[1] == "X")) ? 2 : 0;
        require(b.length - start == 64, "PRIVATE_KEY: expected 32 bytes of hex");
        for (uint256 i = start; i < b.length; ++i) {
            uint8 c = uint8(b[i]);
            uint8 v;
            if (c >= 48 && c <= 57) v = c - 48;
            else if (c >= 97 && c <= 102) v = c - 87;
            else if (c >= 65 && c <= 70) v = c - 55;
            else revert("PRIVATE_KEY: non-hex character");
            k = (k << 4) | v;
        }
    }

    function _recorded(string memory chain, string memory name) internal view returns (address a) {
        string memory json = vm.readFile(REG);
        string memory key = string.concat(".", chain, ".contracts.", name);
        if (!vm.keyExistsJson(json, key)) return address(0);
        a = vm.parseJsonAddress(json, key);
        // CLAUDE.md rule 7: never silently redeploy an address that is already recorded.
        require(
            a.code.length != 0, string.concat("recorded ", name, " has no code on this chain; ask before redeploying")
        );
    }

    function _record(string memory chain, string memory name, address a) internal {
        if (!broadcasting) return;
        vm.writeJson(vm.toString(a), REG, string.concat(".", chain, ".contracts.", name));
    }

    function _recordString(string memory chain, string memory name, string memory v) internal {
        if (!broadcasting) return;
        vm.writeJson(string.concat("\"", v, "\""), REG, string.concat(".", chain, ".", name));
    }
}

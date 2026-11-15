// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test, Vm } from "forge-std/Test.sol";
import { Ownable } from "solady/auth/Ownable.sol";

import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { Currency } from "v4-core/types/Currency.sol";
import { SwapParams, ModifyLiquidityParams } from "v4-core/types/PoolOperation.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";
import { PoolSwapTest } from "v4-core/test/PoolSwapTest.sol";
import { PoolModifyLiquidityTest } from "v4-core/test/PoolModifyLiquidityTest.sol";

import { PingOrigin } from "../../src/spike/PingOrigin.sol";
import { PingReactive } from "../../src/spike/PingReactive.sol";
import { PingReceiver } from "../../src/spike/PingReceiver.sol";
import { TestToken } from "../../src/TestToken.sol";
import { M1Lib } from "../../script/M1Lib.sol";
import { MockSystemContract, MockCallbackProxy, OmniSim } from "../utils/OmniSim.sol";

/// @notice Loop simulation for the M1 spike: origin event → PingReactive.react() → captured callback request →
///         MockCallbackProxy (overwrites first arg) → PingReceiver.onPing.
contract PingLoopTest is Test {
    uint256 constant BASE = 84532;
    uint256 constant UNICHAIN = 1301;
    uint64 constant GAS_LIMIT = 300_000;
    bytes32 constant PING_SIG = keccak256("Ping(uint256,bool,uint256)");
    bytes32 constant SWAP_SIG = keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)");
    bytes32 constant PINGED_SIG = keccak256("Pinged(address,uint256,uint256,uint256,uint256,uint256,uint256)");

    MockSystemContract sys;
    MockCallbackProxy proxy;
    PingOrigin origin;
    PingOrigin originUni;
    IPoolManager manager;
    PoolSwapTest swapRouter;
    PoolKey key;
    bytes32 poolId;
    PingReactive rc;
    PingReceiver receiver;
    address weth;

    function setUp() public {
        vm.etch(OmniSim.SYSTEM, address(new MockSystemContract()).code);
        sys = MockSystemContract(payable(OmniSim.SYSTEM));
        proxy = new MockCallbackProxy();
        origin = new PingOrigin();
        originUni = new PingOrigin();

        // Real v4 PoolManager + reference pool, so the Swap route is tested against the real event layout.
        manager = IPoolManager(deployCode("PoolManager.sol:PoolManager", abi.encode(address(this))));
        TestToken weth_ = new TestToken("Hedgeline Test WETH", "tWETH", 18, 1_000e18);
        TestToken usdc = new TestToken("Hedgeline Test USDC", "tUSDC", 6, 10_000_000e6);
        weth = address(weth_);
        key = M1Lib.poolKey(weth, address(usdc));
        poolId = M1Lib.poolId(weth, address(usdc));
        manager.initialize(key, M1Lib.initialSqrtPriceX96(weth < address(usdc)));

        PoolModifyLiquidityTest lp = new PoolModifyLiquidityTest(manager);
        swapRouter = new PoolSwapTest(manager);
        weth_.mint(address(this), 100e18);
        usdc.mint(address(this), 1_000_000e6);
        weth_.approve(address(lp), type(uint256).max);
        usdc.approve(address(lp), type(uint256).max);
        weth_.approve(address(swapRouter), type(uint256).max);
        usdc.approve(address(swapRouter), type(uint256).max);
        lp.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(M1Lib.TICK_SPACING),
                tickUpper: TickMath.maxUsableTick(M1Lib.TICK_SPACING),
                liquidityDelta: int256(uint256(M1Lib.LIQUIDITY)),
                salt: 0
            }),
            ""
        );

        rc = new PingReactive{ value: 1 ether }(
            address(origin), address(originUni), address(manager), poolId, GAS_LIMIT
        );
        receiver = new PingReceiver(IPayable(payable(address(proxy))), address(rc));
        rc.setReceiver(address(receiver));
    }

    // ───────────────────────────── helpers ─────────────────────────────

    function _pingLog(uint256 n, bool skip, uint256 chainId, uint256 txHash)
        internal
        returns (IReactive.LogRecord memory)
    {
        vm.recordLogs();
        origin.ping(n, skip);
        Vm.Log memory l = OmniSim.find(vm.getRecordedLogs(), address(origin), PING_SIG);
        return OmniSim.toLogRecord(l, chainId, block.number, txHash);
    }

    function _swapLog(bool zeroForOne, uint256 txHash) internal returns (IReactive.LogRecord memory) {
        // exact input of 0.01 tWETH or 30 tUSDC, whichever token is the input for this direction
        address input = zeroForOne ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1);
        int256 amountIn = input == weth ? -0.01e18 : -30e6;
        vm.recordLogs();
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountIn,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            ""
        );
        Vm.Log memory l = OmniSim.find(vm.getRecordedLogs(), address(manager), SWAP_SIG);
        return OmniSim.toLogRecord(l, BASE, block.number, txHash);
    }

    function _react(IReactive.LogRecord memory r) internal {
        vm.prank(OmniSim.SYSTEM);
        rc.react(r);
    }

    /// Delivers the only captured request through the mock proxy; returns the decoded Pinged event.
    function _deliverOne()
        internal
        returns (uint256 n, uint256 chainId, uint256 blockNo, uint256 txHash, uint256 originTs, uint256 ts)
    {
        assertEq(sys.requestCount(), 1, "exactly one callback request");
        MockSystemContract.Request memory req = sys.request(0);
        assertEq(req.requester, address(rc));
        assertEq(req.config.chainId, BASE);
        assertEq(req.config.recipient, address(receiver));
        assertEq(req.config.gasLimit, GAS_LIMIT);
        assertEq(bytes4(req.config.payload), PingReceiver.onPing.selector);
        (address placeholder) = abi.decode(_slice(req.config.payload, 4, 36), (address));
        assertEq(placeholder, address(0), "first payload arg must be the address(0) placeholder");

        vm.recordLogs();
        (bool ok,) = proxy.deliver(address(rc), req.config);
        assertTrue(ok, "callback reverted");
        Vm.Log memory l = OmniSim.find(vm.getRecordedLogs(), address(receiver), PINGED_SIG);
        assertEq(address(uint160(uint256(l.topics[1]))), address(rc));
        n = uint256(l.topics[2]);
        txHash = uint256(l.topics[3]);
        (chainId, blockNo, originTs, ts) = abi.decode(l.data, (uint256, uint256, uint256, uint256));
    }

    function _slice(bytes memory b, uint256 from, uint256 to) internal pure returns (bytes memory out) {
        out = new bytes(to - from);
        for (uint256 i; i < out.length; ++i) {
            out[i] = b[from + i];
        }
    }

    // ───────────────────────────── subscriptions ─────────────────────────────

    function test_constructorSubscribesThreeRoutes() public view {
        assertEq(sys.subCount(), 3);
        uint256 ignore = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

        MockSystemContract.Sub memory a = sys.sub(0);
        assertEq(a.chainId, BASE);
        assertEq(a.contractAddr, address(origin));
        assertEq(a.topic0, uint256(PING_SIG));
        assertEq(a.topic1, ignore);
        assertEq(a.topic2, ignore);
        assertEq(a.topic3, ignore);

        MockSystemContract.Sub memory b = sys.sub(1);
        assertEq(b.chainId, UNICHAIN);
        assertEq(b.contractAddr, address(originUni), "Unichain subscription uses the Unichain origin arg");
        assertEq(b.topic0, uint256(PING_SIG));

        MockSystemContract.Sub memory c = sys.sub(2);
        assertEq(c.chainId, BASE);
        assertEq(c.contractAddr, address(manager));
        assertEq(c.topic0, uint256(SWAP_SIG));
        assertEq(c.topic0, rc.SWAP_TOPIC0(), "Swap topic0 matches FACTS.md");
        assertEq(c.topic1, uint256(poolId));
        assertEq(c.topic2, ignore);
        assertEq(c.topic3, ignore);
        assertEq(address(rc).balance, 1 ether);
    }

    function test_constructorRejectsGasLimitBelowProxyMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(PingReactive.CallbackGasTooLow.selector, uint64(99_999)));
        new PingReactive(address(origin), address(origin), address(manager), poolId, 99_999);
    }

    // ───────────────────────────── E1 / E2 / E3 / E4 routes ─────────────────────────────

    function test_E1_basePingFullLoop() public {
        vm.warp(1_800_000_000);
        IReactive.LogRecord memory r = _pingLog(7, false, BASE, 0xabc1);
        vm.expectEmit(address(rc));
        emit PingReactive.Relayed(0xabc1, BASE, 7);
        _react(r);
        vm.warp(1_800_000_003);
        (uint256 n, uint256 c, uint256 bn, uint256 txh, uint256 ots, uint256 ts) = _deliverOne();
        assertEq(n, 7);
        assertEq(c, BASE);
        assertEq(bn, block.number);
        assertEq(txh, 0xabc1);
        assertEq(ots, 1_800_000_000, "origin timestamp from Ping data");
        assertEq(ts, 1_800_000_003);
    }

    function test_E2_unichainPingFullLoop() public {
        IReactive.LogRecord memory r = _pingLog(42, false, UNICHAIN, 0xabc2);
        _react(r);
        (uint256 n, uint256 c,, uint256 txh, uint256 ots,) = _deliverOne();
        assertEq(n, 42);
        assertEq(c, UNICHAIN, "origin chain carried through");
        assertEq(txh, 0xabc2);
        assertEq(ots, block.timestamp);
    }

    function test_E3_baseSwapFullLoop_bothDirections() public {
        for (uint256 i; i < 2; ++i) {
            sys.clear();
            bool zeroForOne = i == 0;
            IReactive.LogRecord memory r = _swapLog(zeroForOne, 0xabc3 + i);
            assertEq(r.opCode, 3);
            assertEq(r.topic1, uint256(poolId));
            _react(r);
            (uint256 n, uint256 c,, uint256 txh, uint256 ots,) = _deliverOne();
            (uint160 sqrtAfter,,,) = _slot0();
            assertEq(n, sqrtAfter, "n = post-swap sqrtPriceX96 decoded from Swap data word 2");
            assertEq(c, BASE);
            assertEq(txh, 0xabc3 + i);
            assertEq(ots, 0, "Swap route has no origin timestamp");
        }
    }

    function test_E4_skipEmitsSkippedAndRequestsNoCallback() public {
        IReactive.LogRecord memory r = _pingLog(9, true, BASE, 0xabc4);
        vm.expectEmit(address(rc));
        emit PingReactive.Skipped(0xabc4, BASE, 9, 1);
        _react(r);
        assertEq(sys.requestCount(), 0, "skip path must not request a callback");
    }

    // ───────────────────────────── react() never reverts as a filter ─────────────────────────────

    function test_unwiredReceiverSkipsWithReason2() public {
        rc.setReceiver(address(0));
        IReactive.LogRecord memory r = _pingLog(1, false, BASE, 0xabc5);
        vm.expectEmit(address(rc));
        emit PingReactive.Skipped(0xabc5, BASE, 1, 2);
        _react(r);
        assertEq(sys.requestCount(), 0);
    }

    function test_unmatchedLogsFallThrough() public {
        IReactive.LogRecord memory r = _pingLog(1, false, BASE, 1);

        IReactive.LogRecord memory wrongTopic = r;
        wrongTopic.topic0 = uint256(keccak256("Other()"));
        _react(wrongTopic);

        IReactive.LogRecord memory wrongOp = _pingLog(1, false, BASE, 1);
        wrongOp.opCode = 3;
        _react(wrongOp);

        IReactive.LogRecord memory shortData = _pingLog(1, false, BASE, 1);
        shortData.data = hex"01";
        _react(shortData);

        IReactive.LogRecord memory s = _swapLog(true, 2);
        IReactive.LogRecord memory otherPool = _swapLog(true, 2);
        otherPool.topic1 = uint256(keccak256("other pool"));
        _react(otherPool);
        IReactive.LogRecord memory swapWrongOp = _swapLog(true, 2);
        swapWrongOp.opCode = 2;
        _react(swapWrongOp);
        s.data = new bytes(95);
        _react(s);

        assertEq(sys.requestCount(), 0, "no callbacks for unmatched logs");
    }

    /// KNOWN GAP (security review M1, copy-forward): react() does not check log_.chainId / contractAddress, and the
    /// poolId is chain-independent (same CREATE2 tokens on both chains). A Swap LogRecord claiming another chain is
    /// relayed. The subscription filter prevents this on-chain today; HedgelineReactive (M3) must check both and
    /// this test must then flip to assert no request.
    function test_knownGap_swapFromOtherChainIsRelayed() public {
        IReactive.LogRecord memory r = _swapLog(true, 0xdead);
        r.chainId = UNICHAIN;
        _react(r);
        assertEq(sys.requestCount(), 1);
    }

    function test_nonBooleanSkipWordDoesNotRevert() public {
        IReactive.LogRecord memory r = _pingLog(3, false, BASE, 1);
        r.data = abi.encode(uint256(2), uint256(123));
        _react(r); // decoded as uint256: treated as skip, no revert
        assertEq(sys.requestCount(), 0);
    }

    function testFuzz_reactNeverReverts(uint256 topic0Choice, uint256 opCode, bytes calldata data, uint256 topic1)
        public
    {
        IReactive.LogRecord memory r;
        r.topic0 = topic0Choice % 3 == 0 ? uint256(PING_SIG) : topic0Choice % 3 == 1 ? uint256(SWAP_SIG) : topic0Choice;
        r.opCode = opCode % 5;
        r.data = data;
        r.topic1 = topic1 % 2 == 0 ? uint256(poolId) : topic1;
        r.chainId = BASE;
        _react(r);
    }

    // ───────────────────────────── access control ─────────────────────────────

    function test_reactOnlySystem() public {
        IReactive.LogRecord memory r = _pingLog(1, false, BASE, 1);
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), OmniSim.SYSTEM));
        rc.react(r);
    }

    function test_setReceiverOnlyOwner() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        rc.setReceiver(address(1));
    }

    function test_onPingRequiresProxyAndReactiveSender() public {
        // not the proxy
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(proxy)));
        receiver.onPing(address(rc), 1, BASE, 1, 1, 1);

        // proxy, but injected sender is not our reactive contract (e.g. someone else's RC targeting us)
        address imposter = makeAddr("imposterReactive");
        vm.prank(address(proxy));
        vm.expectRevert(abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, imposter, address(rc)));
        receiver.onPing(imposter, 1, BASE, 1, 1, 1);
    }

    function test_proxyRejectsCallbackFromOtherReactive() public {
        IReactive.LogRecord memory r = _pingLog(5, false, BASE, 1);
        _react(r);
        MockSystemContract.Request memory req = sys.request(0);
        (bool ok, bytes memory ret) = proxy.deliver(makeAddr("otherRC"), req.config);
        assertFalse(ok);
        assertEq(bytes4(ret), AbstractCallback.CallbackNotAuthorized.selector);
    }

    function test_coverDebtNoopsWithZeroDebt() public {
        rc.coverDebt();
        receiver.coverDebt();
    }

    // ───────────────────────────── gas ─────────────────────────────

    /// react() must stay far below the 900k reactive cap; callback well under the requested limit.
    function test_gas_reactAndCallback() public {
        IReactive.LogRecord memory ping = _pingLog(11, false, BASE, 1);
        IReactive.LogRecord memory skip = _pingLog(12, true, BASE, 2);
        IReactive.LogRecord memory swap = _swapLog(true, 3);

        // Capture one real request first (for the callback measurement), then switch the mock to light mode.
        _react(ping);
        bytes memory p = sys.request(0).config.payload;
        sys.setLight(true);

        uint256 reactPingGas = _gasOfReact(ping);
        uint256 reactSkipGas = _gasOfReact(skip);
        uint256 reactSwapGas = _gasOfReact(swap);
        assertEq(sys.lightCount(), 2, "ping + swap requested, skip did not");

        address a = address(rc);
        assembly ("memory-safe") {
            mstore(add(p, 36), a)
        }
        vm.prank(address(proxy));
        uint256 g0 = gasleft();
        (bool ok,) = address(receiver).call(p);
        uint256 onPingGas = g0 - gasleft();
        assertTrue(ok);

        emit log_named_uint(
            "react(Ping) gas, caller-side only (mock system); on-chain receipt is the real figure", reactPingGas
        );
        emit log_named_uint("react(Ping skip) gas", reactSkipGas);
        emit log_named_uint("react(Swap) gas, caller-side only (mock system)", reactSwapGas);
        emit log_named_uint("onPing gas (call into receiver)", onPingGas);
        assertLt(reactPingGas, 100_000); // includes the mock's first lightCount SSTORE (~22k)
        assertLt(reactSwapGas, 100_000);
        assertLt(reactSkipGas, 40_000);
        assertLt(onPingGas, GAS_LIMIT * 60 / 100);
    }

    function _gasOfReact(IReactive.LogRecord memory r) internal returns (uint256 used) {
        vm.prank(OmniSim.SYSTEM);
        uint256 g0 = gasleft();
        rc.react(r);
        used = g0 - gasleft();
    }

    function _slot0() internal view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) {
        bytes32 slot = keccak256(abi.encodePacked(poolId, bytes32(uint256(6)))); // StateLibrary.POOLS_SLOT = 6
        bytes32 data = manager.extsload(slot);
        sqrtPriceX96 = uint160(uint256(data));
        tick = int24(int256(uint256(data) >> 160));
        protocolFee = uint24(uint256(data) >> 184);
        lpFee = uint24(uint256(data) >> 208);
    }
}

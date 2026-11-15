// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";

// @reactive/ -> lib/reactive-lib-omni/
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";

// v4-core/, @uniswap/v4-core/, solady/
import { TickMath } from "v4-core/libraries/TickMath.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";

/// @dev Trivial Omni-style reactive contract. Proves the @reactive/ remapping and the Omni API shape.
contract SanityReactive is AbstractReactive {
    uint256 public immutable topic0;
    address public immutable recipient;

    constructor(uint256 topic0_, address recipient_) payable {
        topic0 = topic0_;
        recipient = recipient_;
        SYSTEM.subscribe(84532, address(0xBEEF), topic0_, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        if (log_.topic0 != topic0) return; // fall through, never revert as a filter
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: 84532,
                recipient: recipient,
                gasLimit: 1_000_000,
                payload: abi.encodeWithSignature("pong(address,uint256)", address(0), log_.blockNumber)
            })
        );
    }
}

/// @dev Trivial Omni-style callback contract.
contract SanityCallback is AbstractCallback {
    uint256 public last;

    constructor(IPayable proxy_, address reactive_) payable AbstractCallback(proxy_, reactive_) { }

    function pong(address reactive_, uint256 n_) external onlyServiceProvider onlyCallbackSender(reactive_) {
        last = n_;
    }
}

contract SanityToken is ERC20 {
    function name() public pure override returns (string memory) {
        return "t";
    }

    function symbol() public pure override returns (string memory) {
        return "t";
    }
}

/// @dev Minimal stand-in for the system contract: records subscriptions and callback requests.
contract MockSystem {
    uint256 public subscriptions;
    ISystemContract.CallbackConfiguration_V_1_0 internal _last;

    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external {
        subscriptions++;
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config_) external {
        _last = config_;
    }

    function last() external view returns (ISystemContract.CallbackConfiguration_V_1_0 memory) {
        return _last;
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable { }
}

contract RemappingsTest is Test {
    address constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 constant TOPIC = uint256(keccak256("Ping(uint256,uint256)"));
    address proxy = makeAddr("callbackProxy");

    SanityReactive rc;
    SanityCallback cb;

    function setUp() public {
        vm.etch(SYSTEM_ADDR, address(new MockSystem()).code);
        rc = new SanityReactive(TOPIC, address(0xCAFE));
        cb = new SanityCallback(IPayable(payable(proxy)), address(rc));
    }

    function test_reactiveLibConstants() public view {
        assertEq(address(rc._SERVICE_PROVIDER()), SYSTEM_ADDR);
        assertEq(MockSystem(payable(SYSTEM_ADDR)).subscriptions(), 1);
        assertEq(cb._CALLBACK_SENDER(), address(rc));
        assertEq(address(cb._SERVICE_PROVIDER()), proxy);
    }

    function test_reactOnlySystem() public {
        IReactive.LogRecord memory log_;
        log_.topic0 = TOPIC;
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), SYSTEM_ADDR));
        rc.react(log_);
    }

    function test_reactRequestsCallbackWithPlaceholder() public {
        IReactive.LogRecord memory log_;
        log_.topic0 = TOPIC;
        log_.blockNumber = 42;
        vm.prank(SYSTEM_ADDR);
        rc.react(log_);
        ISystemContract.CallbackConfiguration_V_1_0 memory c = MockSystem(payable(SYSTEM_ADDR)).last();
        assertEq(c.chainId, 84532);
        assertEq(c.recipient, address(0xCAFE));
        (address placeholder, uint256 n) = abi.decode(_stripSelector(c.payload), (address, uint256));
        assertEq(placeholder, address(0));
        assertEq(n, 42);
    }

    function test_callbackNeedsBothModifiers() public {
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), proxy));
        cb.pong(address(rc), 1);

        vm.prank(proxy);
        vm.expectRevert(
            abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, address(this), address(rc))
        );
        cb.pong(address(this), 1);

        vm.prank(proxy);
        cb.pong(address(rc), 7);
        assertEq(cb.last(), 7);
    }

    function test_v4CoreAndSoladyResolve() public {
        assertEq(TickMath.getSqrtPriceAtTick(0), 2 ** 96);
        assertEq(SqrtPriceMath.getAmount0Delta(2 ** 96, 2 ** 97, 1e18, false), 0.5e18);
        assertEq(new SanityToken().totalSupply(), 0);
    }

    function _stripSelector(bytes memory p) internal pure returns (bytes memory out) {
        out = new bytes(p.length - 4);
        for (uint256 i; i < out.length; ++i) {
            out[i] = p[i + 4];
        }
    }
}

contract V4ArtifactTest is Test {
    function test_poolManagerDeploysFromArtifact() public {
        address pm = deployCode("PoolManager.sol:PoolManager", abi.encode(address(this)));
        assertGt(pm.code.length, 0);
    }
}

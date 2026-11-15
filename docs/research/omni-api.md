# reactive-lib-omni API reference

Source: `lib/reactive-lib-omni` at tag **v0.1.0**, commit `3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8` (read 2026-11-16).
Every file: `// SPDX-License-Identifier: UNLICENSED` and **`pragma solidity ^0.8.29;`**. No LICENSE file in the repo.

Files: `src/base/{AbstractPayer,AbstractReactive,AbstractCallback}.sol`, `src/interfaces/{IPayer,IPayable,IReactive,ISubscriptionService,ISystemContract}.sol`.
Import prefix (our `remappings.txt`): `@reactive/=lib/reactive-lib-omni/` → `import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";`

## Inheritance

```
IPayer ──────────────┐
  └─ IReactive        │
AbstractPayer is IPayer
  ├─ AbstractReactive is AbstractPayer, IReactive     (service provider = SYSTEM)
  └─ AbstractCallback is AbstractPayer                (service provider = callback proxy)
IPayable  (system contract + callback proxies implement it)
ISubscriptionService
ISystemContract is IPayable, ISubscriptionService
```

A contract cannot inherit both `AbstractReactive` and `AbstractCallback` (both set the single immutable `_SERVICE_PROVIDER` via `AbstractPayer`'s constructor).

## `AbstractPayer` (abstract, is `IPayer`)

| Member | Signature | Notes |
|---|---|---|
| error | `NotAuthorized(address sender_, address provider_)` | thrown by `onlyServiceProvider` |
| error | `InsufficientFunds(uint256 required_, uint256 available_)` | `_pay` with balance < amount |
| error | `TransferFailed()` | ETH transfer to provider failed |
| immutable | `IPayable public immutable _SERVICE_PROVIDER` | set in constructor |
| constructor | `constructor(IPayable serviceProvider_)` | |
| receive | `receive() virtual external payable {}` | overridable |
| modifier | `onlyServiceProvider()` | `msg.sender == address(_SERVICE_PROVIDER)` else `NotAuthorized(msg.sender, provider)` |
| fn | `function pay(uint256 amount_) external onlyServiceProvider` | pays `amount_` to `msg.sender` (the provider). Don't override. |
| fn | `function _coverDebt() internal` | reads `_SERVICE_PROVIDER.debt(address(this))`, pays it from own balance. **Internal — expose a `coverDebt()` wrapper.** |
| fn | `function _pay(address payable recipient_, uint256 amount_) internal` | reverts `InsufficientFunds`; no-op if `amount_ == 0` |

## `AbstractReactive` (abstract, is `AbstractPayer, IReactive`)

```solidity
ISystemContract internal constant SYSTEM = ISystemContract(payable(0x8888888888888888888888888888888888888888));
uint256 internal constant REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
constructor() AbstractPayer(SYSTEM) {}
modifier onlySystem() { _onlyServiceProvider(); _; }   // identical check to onlyServiceProvider
```

- The constructor is **not payable** in the base; declare our constructor `payable` to fund at deploy.
- `react()` must be implemented (abstract via `IReactive`). Interface declares `LogRecord calldata log_`; the docs and our sanity test implement it as `LogRecord memory log_` — compiles fine (verified in `contracts/test/unit/Remappings.t.sol`).
- No `vm`, `vmOnly`, `service`, or ReactVM concepts exist.

## `AbstractCallback` (abstract, is `AbstractPayer`)

```solidity
error CallbackNotAuthorized(address sender_, address expectedSender_);
address public immutable _CALLBACK_SENDER;
constructor(IPayable callbackProxy_, address callbackSender_) AbstractPayer(callbackProxy_) { _CALLBACK_SENDER = callbackSender_; }
modifier onlyCallbackSender(address callbackSender_)   // reverts CallbackNotAuthorized(callbackSender_, _CALLBACK_SENDER)
```

- `_CALLBACK_SENDER` is immutable, no setter: wrong reactive address ⇒ redeploy.
- Every callback fn: `(address reactive_, ...) external onlyServiceProvider onlyCallbackSender(reactive_)`.

## `IReactive` (interface, is `IPayer`)

```solidity
struct LogRecord {
    uint256 chainId;
    address contractAddress;
    uint256 topic0;
    uint256 topic1;
    uint256 topic2;
    uint256 topic3;
    bytes data;          // ABI-encoded non-indexed params only
    uint256 blockNumber;
    uint256 opCode;      // number of topics (LOG3 => 3)
    uint256 blockHash;   // uint256, not bytes32
    uint256 txHash;      // uint256, not bytes32
    uint256 logIndex;
}
event Callback(uint256 indexed chainId_, address indexed contract_, uint64 indexed gasLimit_, bytes payload_); // DEPRECATED — do not use
function react(LogRecord calldata log_) external;
```

**No timestamp field.** Unused topic slots are `0` — use `opCode` to know how many topics existed.

## `IPayer`

```solidity
function pay(uint256 amount_) external;
receive() external payable;
```

## `IPayable` (system contract + callback proxies)

```solidity
receive() external payable;
function debt(address contract_) external view returns (uint256 debt_);
```

Not in the interface but present on-chain and documented in Economy: `depositTo(address) payable`, `reserves(address) view`,
`debts(address)` (alias of `debt`), `_gasPriceCoeffPer1000()`, `_extraGas()`, `_maxChargeGas()`, and on the system contract
`getCallbacks(uint256)((uint256,address,uint256,uint256,uint256,bytes)[])`.

## `ISubscriptionService`

```solidity
function subscribe(uint256 chainId_, address contract_, uint256 topic0_, uint256 topic1_, uint256 topic2_, uint256 topic3_) external;
function unsubscribe(uint256 chainId_, address contract_, uint256 topic0_, uint256 topic1_, uint256 topic2_, uint256 topic3_) external;
```

Wildcards: `chainId_ = 0`, `contract_ = address(0)`, `topicN_ = REACTIVE_IGNORE`. At least one criterion specific. Equality only, no OR. `unsubscribe` must match all six exactly.

## `ISystemContract` (is `IPayable, ISubscriptionService`)

```solidity
enum CallbackVersion { V_1_0 }
struct CallbackConfiguration_V_1_0 {
    uint256 chainId;    // destination
    address recipient;  // callback contract on destination
    uint64  gasLimit;   // >= 100_000 or the request is ignored
    bytes   payload;    // abi.encodeWithSignature("fn(address,...)", address(0), ...)
}
function requestCallback(CallbackVersion version_, bytes memory config_) external;      // reverts InvalidCallbackVersion on unknown
function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config_) external;   // use this
```

System contract emits (per docs, not in the lib):
`event CallbackRequest(uint256 indexed chainId, address indexed sender, address indexed recipient, CallbackVersion version, bytes configuration);`

## Minimal Omni skeletons (compile-checked in `contracts/test/unit/Remappings.t.sol`)

```solidity
contract R is AbstractReactive {
    constructor(...) payable { SYSTEM.subscribe(chainId, origin, topic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE); }
    function react(LogRecord memory log_) external onlySystem {
        if (log_.topic0 != T || log_.opCode != N) return;           // fall through, never revert
        SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0({
            chainId: 84532, recipient: hedger, gasLimit: 1_000_000,
            payload: abi.encodeWithSignature("fn(address,uint256)", address(0), x)
        }));
    }
    function coverDebt() external { _coverDebt(); }
}

contract C is AbstractCallback {
    constructor(IPayable proxy_, address reactive_) payable AbstractCallback(proxy_, reactive_) {}
    function fn(address reactive_, uint256 x) external onlyServiceProvider onlyCallbackSender(reactive_) { ... }
    function coverDebt() external { _coverDebt(); }
}
```

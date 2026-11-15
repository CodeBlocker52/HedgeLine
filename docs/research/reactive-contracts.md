<!-- Source: https://dev.reactive.network/reactive-contracts -- fetched 2026-11-16 via curl, converted with a stdlib HTML->MD script. Code blocks verbatim. -->

![Reactive Contracts Image](/assets/images/reactive-contracts-d7896542afec1a9f8f95baf928e2d261.jpg)

## Overview

A reactive contract is an ordinary Solidity contract with one extra ability: it can subscribe to events on any chain Reactive Network monitors. When a matching log appears, the system contract calls `react()`, where the contract can update its state, request a callback on another chain, or change its own subscriptions. Contracts on the receiving end of a callback are covered in [Callback Contracts](/callback-contracts).

## Inheritance

[AbstractReactive](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractReactive.sol) is the base you inherit, and [IReactive](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/interfaces/IReactive.sol) is needed for the `/// @inheritdoc IReactive` tag, though not for `LogRecord`, which inheritance already provides. [ISystemContract](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/interfaces/ISystemContract.sol) is needed only when you name the callback configuration struct, but a contract that observes events without ever acting on them is the exception, so expect to [request callbacks](#requesting-callbacks) and import it from the start.

```solidity
// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

contract MyReactive is AbstractReactive {
    uint256 private immutable _originChainId;
    address private immutable _originContract;
    uint256 private immutable _topic0;

    // `payable` so the contract can be funded at deployment.
    constructor(uint256 originChainId_, address originContract_, uint256 topic0_) payable {
        _originChainId = originChainId_;
        _originContract = originContract_;
        _topic0 = topic0_;

        SYSTEM.subscribe(
            originChainId_,
            originContract_,
            topic0_,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        // Your logic here.
    }
}
```

That compiles, deploys, and starts receiving events. Three requirements are doing the work:

-

**Inherit [AbstractReactive](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractReactive.sol).** It supplies `SYSTEM`, `REACTIVE_IGNORE`, and `onlySystem`, and brings [AbstractPayer](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractPayer.sol) with it.
-

**Implement `react()` with `onlySystem`.** [IReactive](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/interfaces/IReactive.sol) leaves it abstract, so the contract won't compile without it. The modifier checks `msg.sender` against the service provider, which for a reactive contract is `SYSTEM` at `0x8888888888888888888888888888888888888888`, and reverts with `NotAuthorized` for anyone else. Without it, a caller can hand your contract a fabricated log record.
-

**Keep the contract funded.** Reactive transactions cost gas and the contract pays for them. A `payable` constructor lets you fund at deployment, which is the simplest route, but it isn't required: `receive()` is inherited as payable, so a contract can be topped up afterwards, and `depositTo()` credits it without its cooperation. What matters is that funds are there before the first event arrives. [Economy](/economy) covers reserves, charges, and debt.

Between the two base contracts, these are the names you inherit:

| Name | Comes from | What it's for |
|---|---|---|
| `SYSTEM` | [AbstractReactive](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractReactive.sol) | The system contract at `0x8888888888888888888888888888888888888888`, where you subscribe and request callbacks |
| `REACTIVE_IGNORE` | [AbstractReactive](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractReactive.sol) | Wildcard value for any topic position |
| `onlySystem` | [AbstractReactive](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractReactive.sol) | Rejects `react()` calls from anyone but the system contract |
| `LogRecord` | [IReactive](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/interfaces/IReactive.sol) | The struct `react()` receives |
| `_SERVICE_PROVIDER` | [AbstractPayer](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractPayer.sol) | The contract allowed to bill you, `SYSTEM` for a reactive contract |
| `onlyServiceProvider` | [AbstractPayer](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractPayer.sol) | Rejects calls from anyone but that service provider. `onlySystem` is this same check under a clearer name |
| `pay(uint256)` | [AbstractPayer](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractPayer.sol) | Already implemented, and it verifies the caller. Don't write your own |
| `_coverDebt()` | [AbstractPayer](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractPayer.sol) | Settles outstanding debt from the contract's balance. Internal, so expose it yourself if you want it callable |
| `receive()` | [AbstractPayer](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractPayer.sol) | Accepts funds, `virtual` so you can override it |

## Subscriptions

A subscription tells Reactive which logs should reach your contract. Each one is a set of criteria passed to `SYSTEM.subscribe()`, and both methods take the same six arguments:

```solidity
function subscribe(
    uint256 chainId_,
    address contract_,
    uint256 topic0_,
    uint256 topic1_,
    uint256 topic2_,
    uint256 topic3_
) external;

function unsubscribe(
    uint256 chainId_,
    address contract_,
    uint256 topic0_,
    uint256 topic1_,
    uint256 topic2_,
    uint256 topic3_
) external;
```

Each criterion narrows or widens independently. `topic0` is normally the event signature hash, with topics 1-3 holding indexed parameters, and any position can be left open:

| Criterion | Wildcard | Matches |
|---|---|---|
| `chainId_` | `0` | Any chain |
| `contract_` | `address(0)` | Any contract on the specified chain |
| `topic0_` to `topic3_` | `REACTIVE_IGNORE` | Any value in that position |

Combining them gives you the usual shapes:

| Subscription | `chainId_` | `contract_` | `topic0_` |
|---|---|---|---|
| Every event from one contract | specific | specific | `REACTIVE_IGNORE` |
| One event type across a chain | specific | `address(0)` | specific |
| One event from one contract | specific | specific | specific |
 Criteria Limit

At least one criterion has to be specific. Subscribing to every event on every contract on every chain isn't allowed.

### Limits Worth Knowing

**Equality only.** Criteria match exact values. There are no ranges, comparisons, or bitwise filters.

**One criteria set per subscription.** There's no way to express `OR` within a single subscription. Call `subscribe()` once per combination you want, which is also how a contract watches several contracts or several event types at once.

**Duplicates are allowed but pointless.** Two identical subscriptions behave as one, and you pay gas for both calls.

**Subscriptions live in the node, not in contract storage.** You can't read your own back on-chain, so track them yourself if your logic depends on knowing them.

### Changing Subscriptions At Runtime

Subscribing isn't limited to the constructor. A contract can widen, narrow, or drop what it watches at any point, including from inside `react()`. Wrapping both calls in internal helpers keeps the six criteria in one place, which matters because `unsubscribe()` removes a subscription matching all six arguments exactly. Any drift between the two calls leaves the subscription in place and fails silently.

```solidity
function _subscribe() internal {
    SYSTEM.subscribe(
        _originChainId,
        _originContract,
        _topic0,
        REACTIVE_IGNORE,
        REACTIVE_IGNORE,
        REACTIVE_IGNORE
    );
}

function _unsubscribe() internal {
    SYSTEM.unsubscribe(
        _originChainId,
        _originContract,
        _topic0,
        REACTIVE_IGNORE,
        REACTIVE_IGNORE,
        REACTIVE_IGNORE
    );
}
```

A contract that stops and restarts should settle up before resubscribing, since a contract in debt receives nothing:

```solidity
function updateLimit(uint256 limit_) external payable onlyOwner {
    _limit = limit_;

    if (limit_ == 0) {
        _unsubscribe();
    } else {
        _coverDebt();
        _subscribe();
    }
}
```

### Subscribing To CRON Events

The legacy system contract at `0x0000000000000000000000000000000000fffFfF` emits `Cron` events at fixed block intervals, which gives a reactive contract scheduled execution with no polling and no external automation. Only authorized validator root addresses can call its `cron()` method, so these events come from the network itself rather than from anything you deploy.

Each call to `cron()` emits one or more events depending on how the current block number divides. Larger intervals fire less often, and a block divisible by several intervals emits several events.

| Event | Interval | Approximate Time | Topic 0 |
|---|---|---|---|
| `Cron1` | Every block | ~1 second | `0xf02d6ea5c22a71cffe930a4523fcb4f129be6c804db50e4202fb4e0b07ccb514` |
| `Cron10` | Every 10 blocks | ~10 seconds | `0x04463f7c1651e6b9774d7f85c85bb94654e3c46ca79b0c16fb16d4183307b687` |
| `Cron100` | Every 100 blocks | ~2 minutes | `0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70` |
| `Cron1000` | Every 1000 blocks | ~17 minutes | `0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4` |
| `Cron10000` | Every 10,000 blocks | ~3 hours | `0xd214e1d84db704ed42d37f538ea9bf71e44ba28bc1cc088b2f5deca654677a56` |

These are protocol values, so unlike the subscriptions above they're hardcoded. The only difference from any other subscription is that the contract position names the legacy address:

```solidity
address internal constant LEGACY_SYSTEM_ADDR = 0x0000000000000000000000000000000000fffFfF;
uint256 internal constant CRON100_TOPIC_0 = 0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;

function _subscribeToCron() internal {
    SYSTEM.subscribe(
        block.chainid,
        LEGACY_SYSTEM_ADDR,
        CRON100_TOPIC_0,
        REACTIVE_IGNORE,
        REACTIVE_IGNORE,
        REACTIVE_IGNORE
    );
}
```

-

Ticks arrive at the same `react()` as every other subscription, told apart by `topic0`.
-

Every `Cron` event carries one parameter, `number`, the block it fired for. It isn't indexed, so it arrives in `log_.data` as a single `uint256`. Inside `react()` you can usually read `block.number` instead and ignore the payload.
-

Because a single `cron()` call fires every interval the block number divides by, overlapping subscriptions overlap in practice. A contract subscribed to both `Cron1` and `Cron10` gets two separate reactive transactions on every tenth block, and pays for both.
-

Cron subscriptions bill on every tick whether or not your `react()` does anything. Pick the longest interval that fits, and build in a way to switch it off, unsubscribing to pause and resubscribing to resume.
-

A callback can target Reactive Network itself, with `chainId: block.chainid` and `recipient: address(this)`, which runs work in a fresh transaction rather than inside `react()`. The receiving method still needs the guards described in [Callback Contracts](/callback-contracts).

## Reacting To Events

Every subscription a contract holds arrives at the same `react()`, carrying our normalized form of an EVM log:

```solidity
struct LogRecord {
    uint256 chainId;
    address contractAddress;
    uint256 topic0;
    uint256 topic1;
    uint256 topic2;
    uint256 topic3;
    bytes data;
    uint256 blockNumber;
    uint256 opCode;
    uint256 blockHash;
    uint256 txHash;
    uint256 logIndex;
}
```

Three fields need explaining. `data` holds the ABI-encoded non-indexed parameters, and nothing else. `opCode` is how many topics the original log had, so a `LOG3` arrives with `opCode` of `3`. And `blockHash` and `txHash` are `uint256` rather than `bytes32`, so cast them if you're comparing against values from elsewhere.

There are always four topic fields, and positions the original log didn't use are zero. Since `data`'s layout depends on which parameters were indexed, check `opCode` before decoding. With more than one subscription, route on `topic0` first:

```solidity
/// @inheritdoc IReactive
function react(LogRecord memory log_) external onlySystem {
    if (log_.topic0 == _topic0 && log_.opCode == 3) {
        uint256 amount = abi.decode(log_.data, ( uint256 ));

        // Handle the event.
    } else if (log_.topic0 == CRON100_TOPIC_0) {
        // Run scheduled work.
    }
}
```

An ERC-20 `Transfer(address indexed from, address indexed to, uint256 value)` is the familiar case: three topics, both addresses already in the record, and only the amount left in `data`. The same event with unindexed parameters would arrive as a `LOG1` with all three values packed into `data`, which is why the count is worth checking. Where several non-indexed parameters are in play, decode them as a tuple in declaration order.

-

Logs that don't match should fall through and cost nothing extra. Reverting as a filter is a mistake: the system contract catches it, emits `ReactiveContractReverted`, and still bills you for the gas burned.
-

A zero in a topic position doesn't prove the log had fewer topics, since a topic can legitimately be zero. An ERC-20 mint emits `Transfer` with `from` as `address(0)`. `opCode` is the reliable count.
-

`react()` can do anything an ordinary function can, including subscribing, unsubscribing, and requesting callbacks. It's a normal transaction on Reactive Network, not a restricted callback context.
-

Where `react()` sits in the wider flow, from the debt check that precedes it to the charge that follows, is laid out in [Economy](/economy).

## Requesting Callbacks

Reacting to an event only changes state on Reactive Network. To act on another chain, ask the system contract to post a callback. This is what `ISystemContract` is imported for, since naming the configuration struct writes that identifier into your own file.

```solidity
enum CallbackVersion { V_1_0 }

function requestCallback(CallbackVersion version_, bytes memory config_) external;
function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config_) external;

struct CallbackConfiguration_V_1_0 {
    uint256 chainId;    // destination network
    address recipient;  // target contract on the destination chain
    uint64 gasLimit;    // execution gas limit
    bytes payload;      // ABI-encoded function call
}
```

Reach for `requestCallbackV_1_0()`, which takes the struct directly with no manual encoding or version flag. `requestCallback()` is the generic entry point for choosing a version at runtime, taking configuration ABI-encoded to match it, and reverting with `InvalidCallbackVersion` on anything it doesn't recognize. Both share one code path, since the typed wrapper encodes your struct and calls the generic method with `CallbackVersion.V_1_0`. That's the only version today; future callback types each get their own, with a matching typed wrapper. Reserve the first argument of your payload

Reactive Network replaces the first 160 bits of the payload with the address of the reactive contract that requested the callback, so the destination can authenticate the sender. Your payload has to declare an `address` there and pass `address(0)` as a placeholder, whatever you name it in Solidity. Forgetting it is the most common way to break a callback.

```solidity
uint64 private constant CALLBACK_GAS_LIMIT = 1000000;

function _requestCallback(uint256 chainId_, address recipient_, uint256 value_) internal {
    bytes memory payload = abi.encodeWithSignature(
        "myCallback(address,uint256)",
        address(0),
        value_
    );

    SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0({
        chainId: chainId_,
        recipient: recipient_,
        gasLimit: CALLBACK_GAS_LIMIT,
        payload: payload
    }));
}
```

-

Requesting a callback doesn't require an incoming event. It's an ordinary call on `SYSTEM`, so a plain external method can do it too, though most requests come from inside `react()`.
-

Callbacks are billed to the recipient on the destination chain, in that chain's native currency, not to the reactive contract that requested them. A recipient in debt receives nothing, and a failed callback still costs it. See [Callback Contracts](/callback-contracts).
-

Set `gasLimit` to cover the destination call. The proxy reserves overhead for charging on top of it, and a limit that's too tight surfaces as a `CallbackFailure` event rather than a revert you can catch.
-

The recipient's address has to be known before you can call it, while the recipient usually needs your contract's address to authenticate the callback. Deploy the reactive contract first, then the recipient with that address, then set the recipient on the reactive contract through an owner-only setter.
-

Emitting a `Callback` event still works for contracts that already rely on it, but it's deprecated.

Either method causes the system contract to emit `CallbackRequest`, which the network picks up to submit the destination transaction. Its three indexed fields are the destination chain, the requesting reactive contract, and the recipient, which makes it cheap for explorers and off-chain infrastructure to filter:

```solidity
event CallbackRequest(
    uint256 indexed chainId,
    address indexed sender,
    address indexed recipient,
    CallbackVersion version,
    bytes configuration
);
```

Writing the contract that receives the callback is covered in [Callback Contracts](/callback-contracts).

## Settling Debt On Demand

A contract in debt receives nothing: the system contract stops delivering reactive transactions until the debt clears. Charges draw on reserves first and [AbstractPayer](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractPayer.sol) settles any shortfall automatically through `pay()`, so this only bites a contract that has run out of both.

`_coverDebt()` settles from the contract's own balance, but it's internal, so expose it yourself if an outside call should be able to trigger it:

```solidity
/// @notice Settles outstanding debt from this contract's own balance.
function coverDebt() external {
    _coverDebt();
}
```

Leaving it open to any caller lets a third party fund the contract and restart it, which is useful for contracts serving other people. Add `onlyOwner` if the balance is meant for anything else, or omit the wrapper entirely and rely on `depositTo()`. [Economy](/economy) covers the trade-offs and the commands.

## Verifying Reactive Contracts

Contracts can be verified during or after deployment using the Sourcify endpoint. Sourcify is a decentralized verification service that matches deployed bytecode with source code, making contracts auditable and transparent.

### Verify After Deployment

```bash
forge verify-contract \
--verifier sourcify \
--chain-id $CHAIN_ID \
$CONTRACT_ADDR $CONTRACT_NAME
```

Replace:

- `$CHAIN_ID` → `1597` (Reactive Mainnet) or `5318007` (Lasna Testnet)
- `$CONTRACT_ADDR` → deployed contract address
- `$CONTRACT_NAME` → contract name (e.g. `MyContract`)

### Verify On Deployment

```bash
forge create \
--verifier sourcify \
--verify \
--chain-id $CHAIN_ID \
--private-key $PRIVATE_KEY \
$PATH
```

Replace:

- `$CHAIN_ID` → `1597` (Reactive Mainnet) or `5318007` (Lasna Testnet)
- `$PATH` → e.g. `src/MyContract.sol:MyContract`
- `$PRIVATE_KEY` → deployer key

Example:

```bash
forge create \
  --broadcast \
  --rpc-url $REACTIVE_RPC_URL \
  --private-key $REACTIVE_PRIVATE_KEY \
  --chain-id $REACTIVE_CHAIN_ID \
  --value 0.01ether \
  --verify \
  --verifier sourcify \
  src/.../MyContract.sol:MyContract \
  --constructor-args \
    $ARGUMENT_1 \
    $ARGUMENT_2 \
    $ARGUMENT_3
```

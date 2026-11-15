<!-- Source: https://dev.reactive.network/origins-and-destinations -- fetched 2026-11-16 via curl, converted with a stdlib HTML->MD script. Code blocks verbatim. -->

![Origins &amp; Destinations Image](/assets/images/origins-and-destinations-6c5623c0411baf75c6180ad0dea60e45.jpg)

## Overview

Reactive contracts can listen to event logs on one chain and trigger actions on another. To describe that flow, we use two roles:

- **Origin:** the chain where events happen and event logs are read from (the event source).
- **Destination:** the chain where Reactive Network delivers a callback transaction (the chain where state changes occur).

Origins and destinations don’t have to be the same. A single reactive contract can subscribe to events from multiple origin chains, and it can send callbacks to one or more destination chains. Your Solidity logic can also choose the destination conditionally.

## Callback Proxy Address

Callbacks are delivered by Reactive Signer, which posts transactions to destination chains. These transactions pass through a callback proxy contract, which makes them verifiable and safe for destination-side contracts.

A destination contract can validate a callback by checking that `msg.sender` is the relevant callback proxy and the original sender from Reactive Network is Reactive Signer.

## Mainnet Chains
 Origin/Destination

Origin is the chain where events originate (and are read from). Destination is the chain where callbacks are delivered in response to those events. Mainnets and testnets must not be mixed: if the origin is a mainnet, the destination must also be a mainnet.

| Chain | Origin | Destination | Chain ID | Callback Proxy | RPC |
|---|---|---|---|---|---|
| [ Arbitrum ](https://www.arbiscan.io/) | ✅ | ✅ | 42161 | `0xaee8d2deBaB5bE353bfec167C58a549923892e11` | [Chainlist](https://chainlist.org/chain/42161) |
| [ Avalanche ](https://avascan.info/) | ✅ | ✅ | 43114 | `0x8bdfC7e564B90b31c49Cf1079d4c44400F4e14B4` | [Chainlist](https://chainlist.org/chain/43114) |
| [ Base ](https://basescan.org/) | ✅ | ✅ | 8453 | `0xCc780DdE33f56f55dE778D42c930959374a4a068` | [Chainlist](https://chainlist.org/chain/8453) |
| [ BSC ](https://bscscan.com/) | ✅ | ✅ | 56 | `0xfc41eE9d3A836b41399BEcce83b06B3e5650f3BB` | [Chainlist](https://chainlist.org/chain/56) |
| [ Ethereum ](https://etherscan.io/) | ✅ | ✅ | 1 | `0xFCE1F192F489c988392aBC16E91e359d540d94Fe` | [Chainlist](https://chainlist.org/chain/1) |
| [ HyperEVM ](https://hyperevmscan.io/) | ✅ | ✅ | 999 | `0x754120EC7a6eF81E4c5c835AA603C63Da64693E6` | [Chainlist](https://chainlist.org/chain/999) |
| [ Reactive ](https://reactscan.net) | ✅ | ✅ | 1597 | `0x8888888888888888888888888888888888888888` | `https://mainnet-rpc.rnk.dev/` |
| [ Robinhood ](https://robinhoodchain.blockscout.com/) | ✅ | ✅ | 4663 | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` | [Chainlist](https://chainlist.org/chain/4663) |
| [ Unichain ](https://uniscan.xyz/) | ✅ | ✅ | 130 | `0x754120EC7a6eF81E4c5c835AA603C63Da64693E6` | [Chainlist](https://chainlist.org/chain/130) |

## Testnet Chains
 Origin/Destination

Origin is the chain where events originate (and are read from). Destination is the chain where callbacks are delivered in response to those events. Mainnets and testnets must not be mixed: if the origin is a testnet, the destination must also be a testnet.

| Chain | Origin | Destination | Chain ID | Callback Proxy | RPC |
|---|---|---|---|---|---|
| [Base Sepolia](https://sepolia.basescan.org) | ✅ | ✅ | 84532 | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` | [Chainlist](https://chainlist.org/chain/84532) |
| [Ethereum Sepolia](https://sepolia.etherscan.io) | ✅ | ✅ | 11155111 | `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` | [Chainlist](https://chainlist.org/chain/11155111) |
| [Reactive Lasna](https://lasna.reactscan.net) | ✅ | ✅ | 5318007 | `0x8888888888888888888888888888888888888888` | `https://lasna-rpc.rnk.dev/` |
| [Unichain Sepolia](https://sepolia.uniscan.xyz) | ✅ | ✅ | 1301 | `0x775c9B990ADe401060B78D0e98684eEf8d2466C1` | [Chainlist](https://chainlist.org/chain/1301) |

<!-- Source: https://dev.reactive.network/reactive-mainnet -- fetched 2026-11-16 via curl, converted with a stdlib HTML->MD script. Code blocks verbatim. -->

![Mainnet Testnet Image](/assets/images/mainnet-testnet-b3975335e38c0dd3e4e291b3e87c6e00.jpg)

## Overview

Reactive Mainnet is the production network for reactive contracts. Lasna Testnet provides a testing environment for development and experimentation before mainnet deployment. System Contract

Reactive Mainnet and Lasna Testnet share the same system contract address: `0x8888888888888888888888888888888888888888`

## Reactive Mainnet

Network parameters:

- **Network Name:** Reactive Mainnet
- **RPC URL:** [https://mainnet-rpc.rnk.dev/](https://mainnet-rpc.rnk.dev/)
- **Chain ID:** 1597
- **Currency Symbol:** REACT
- **Block Explorer:** [https://reactscan.net/](https://reactscan.net/)

## Get Testnet REACT

### Reactive Faucet

To obtain testnet lREACT, send SepETH to one of the faucet contracts:

```json
Ethereum Sepolia: `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`

Base Sepolia: `0x2afaFD298b23b62760711756088F75B7409f5967`
```

Exchange rate: **1 ETH → 100 lREACT**.

Transfers can be made using MetaMask or any Ethereum-compatible wallet. Important

Don't send more than 5 ETH per transaction.

- Maximum sent: 5 ETH
- Maximum received: 500 lREACT

Amounts above 5 ETH are lost and will not generate additional lREACT.

### Terminal Request

You can request lREACT by calling `request(address)` on a faucet contract:

```bash
cast send 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 --rpc-url $ETHEREUM_SEPOLIA_RPC --private-key $ETHEREUM_SEPOLIA_PRIVATE_KEY "request(address)" $WALLET_ADDR --value 0.1ether
```

```bash
cast send 0x2afaFD298b23b62760711756088F75B7409f5967 --rpc-url $BASE_SEPOLIA_RPC --private-key $BASE_SEPOLIA_PRIVATE_KEY "request(address)" $WALLET_ADDR --value 0.1ether
```

## Lasna Testnet

Network parameters:

- **Network Name:** Reactive Lasna
- **RPC URL:** [https://lasna-rpc.rnk.dev/](https://lasna-rpc.rnk.dev/)
- **Chain ID:** 5318007
- **Currency Symbol:** lREACT
- **Block Explorer:** [https://lasna.reactscan.net/](https://lasna.reactscan.net/)

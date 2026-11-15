// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

/// @title PingReceiver (M1 spike, Base Sepolia)
/// @notice Callback contract for the M1 hello loop. Only the Base Sepolia callback proxy may call `onPing`, and only
///         when the proxy-injected first argument equals the PingReactive address fixed at construction.
contract PingReceiver is AbstractCallback {
    event Pinged(
        address indexed reactive,
        uint256 indexed n,
        uint256 originChainId,
        uint256 originBlock,
        uint256 indexed originTxHash,
        uint256 originTimestamp,
        uint256 timestamp
    );

    constructor(IPayable callbackProxy_, address reactive_) payable AbstractCallback(callbackProxy_, reactive_) { }

    /// @param reactive_ overwritten by the network with the requesting reactive contract's address
    /// @param n Ping.n for Ping routes; the post-swap sqrtPriceX96 for the Swap route
    /// @param originTimestamp Ping.timestamp; 0 for the Swap route (LogRecord carries no timestamp)
    function onPing(
        address reactive_,
        uint256 n,
        uint256 originChainId,
        uint256 originBlock,
        uint256 originTxHash,
        uint256 originTimestamp
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        emit Pinged(reactive_, n, originChainId, originBlock, originTxHash, originTimestamp, block.timestamp);
    }

    /// @notice Pays any debt owed to the callback proxy from this contract's balance.
    function coverDebt() external {
        _coverDebt();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Vm } from "forge-std/Vm.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";

/// @dev Stand-in for the Reactive system contract at 0x8888…8888 (etched in tests).
///      Records subscriptions and captures requestCallbackV_1_0 calls instead of delivering them.
contract MockSystemContract {
    struct Sub {
        uint256 chainId;
        address contractAddr;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
    }

    struct Request {
        address requester;
        ISystemContract.CallbackConfiguration_V_1_0 config;
    }

    Sub[] internal _subs;
    Request[] internal _requests;
    /// When true, requests are only counted (no payload SSTOREs), so gas tests measure the caller, not the mock.
    bool public light;
    uint256 public lightCount;

    function subscribe(uint256 c, address a, uint256 t0, uint256 t1, uint256 t2, uint256 t3) external {
        _subs.push(Sub(c, a, t0, t1, t2, t3));
    }

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external { }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config_) external {
        if (light) {
            ++lightCount;
            return;
        }
        _requests.push(Request(msg.sender, config_));
    }

    function setLight(bool light_) external {
        light = light_;
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    function subCount() external view returns (uint256) {
        return _subs.length;
    }

    function sub(uint256 i) external view returns (Sub memory) {
        return _subs[i];
    }

    function requestCount() external view returns (uint256) {
        return _requests.length;
    }

    function request(uint256 i) external view returns (Request memory) {
        return _requests[i];
    }

    function clear() external {
        delete _requests;
    }

    receive() external payable { }
}

/// @dev Stand-in for a destination callback proxy. Like the real one, it overwrites the first payload argument
///      with the requesting reactive contract's address, then calls the recipient with the requested gas limit.
contract MockCallbackProxy {
    function deliver(address reactive_, ISystemContract.CallbackConfiguration_V_1_0 memory config_)
        external
        returns (bool ok, bytes memory ret)
    {
        bytes memory p = config_.payload;
        require(p.length >= 36, "payload too short");
        assembly ("memory-safe") {
            // payload = selector (4 bytes) ‖ word0 (first arg) ‖ ...; word0 starts at p + 32 + 4
            mstore(add(p, 36), reactive_)
        }
        (ok, ret) = config_.recipient.call{ gas: config_.gasLimit }(p);
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable { }
}

library OmniSim {
    address internal constant SYSTEM = 0x8888888888888888888888888888888888888888;

    /// @dev Converts a captured EVM log into the LogRecord the system contract would deliver.
    function toLogRecord(Vm.Log memory l, uint256 chainId, uint256 blockNumber, uint256 txHash)
        internal
        pure
        returns (IReactive.LogRecord memory r)
    {
        r.chainId = chainId;
        r.contractAddress = l.emitter;
        uint256 n = l.topics.length;
        if (n > 0) r.topic0 = uint256(l.topics[0]);
        if (n > 1) r.topic1 = uint256(l.topics[1]);
        if (n > 2) r.topic2 = uint256(l.topics[2]);
        if (n > 3) r.topic3 = uint256(l.topics[3]);
        r.data = l.data;
        r.blockNumber = blockNumber;
        r.opCode = n;
        r.txHash = txHash;
    }

    /// @dev First log in `logs` emitted by `emitter` with `topic0`.
    function find(Vm.Log[] memory logs, address emitter, bytes32 topic0) internal pure returns (Vm.Log memory) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length > 0 && logs[i].topics[0] == topic0) {
                return logs[i];
            }
        }
        revert("OmniSim: log not found");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Ownable } from "solady/auth/Ownable.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title PingReactive (M1 spike, Lasna)
/// @notice Relays three origin routes to PingReceiver on Base Sepolia:
///   S-a  Ping on Base Sepolia PingOrigin
///   S-b  Ping on Unichain Sepolia PingOrigin
///   S-c  PoolManager.Swap on Base Sepolia, topic1 = our reference poolId
/// A Ping with `skip == true` emits `Skipped` and requests no callback.
/// @dev Lean `react()`: routes on topic0, checks opCode and data length before decoding, never reverts as a filter,
///      writes no storage. One SLOAD (`receiver`) per relayed event.
contract PingReactive is AbstractReactive, Ownable {
    /// keccak256("Ping(uint256,bool,uint256)")
    uint256 public constant PING_TOPIC0 = uint256(keccak256("Ping(uint256,bool,uint256)"));
    /// keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)") — FACTS.md §2.3
    uint256 public constant SWAP_TOPIC0 = 0x40e9cecb9f5f1f1c5b9c97dec2917b7ee92e57ba5563708daca94dd84ad7112f;
    uint256 public constant BASE_SEPOLIA = 84532;
    uint256 public constant UNICHAIN_SEPOLIA = 1301;

    address public immutable pingOriginBase;
    address public immutable pingOriginUnichain;
    address public immutable basePoolManager;
    uint256 public immutable poolId;
    uint64 public immutable callbackGasLimit;

    /// PingReceiver on Base Sepolia. Unset (0) until wired; while unset, events are skipped (reason 2).
    address public receiver;

    uint8 internal constant SKIP_FLAG = 1;
    uint8 internal constant SKIP_NO_RECEIVER = 2;

    event ReceiverSet(address receiver);
    /// Callback requested for an origin event. Indexed by origin tx hash so watchers can find this Lasna tx.
    event Relayed(uint256 indexed originTxHash, uint256 indexed originChainId, uint256 n);
    /// No callback requested. reason 1 = Ping.skip, 2 = receiver not set.
    event Skipped(uint256 indexed originTxHash, uint256 indexed originChainId, uint256 n, uint8 reason);

    error CallbackGasTooLow(uint64 gasLimit);

    constructor(
        address pingOriginBase_,
        address pingOriginUnichain_,
        address basePoolManager_,
        bytes32 poolId_,
        uint64 callbackGasLimit_
    ) payable {
        if (callbackGasLimit_ < 100_000) revert CallbackGasTooLow(callbackGasLimit_); // proxy ignores < 100k
        _initializeOwner(msg.sender);
        pingOriginBase = pingOriginBase_;
        pingOriginUnichain = pingOriginUnichain_;
        basePoolManager = basePoolManager_;
        poolId = uint256(poolId_);
        callbackGasLimit = callbackGasLimit_;

        SYSTEM.subscribe(BASE_SEPOLIA, pingOriginBase_, PING_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        SYSTEM.subscribe(
            UNICHAIN_SEPOLIA, pingOriginUnichain_, PING_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
        SYSTEM.subscribe(
            BASE_SEPOLIA, basePoolManager_, SWAP_TOPIC0, uint256(poolId_), REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    function react(LogRecord memory log_) external onlySystem {
        uint256 topic0 = log_.topic0;
        if (topic0 == PING_TOPIC0) {
            // Ping(uint256 indexed n, bool skip, uint256 timestamp): LOG2, data = (skip, timestamp)
            if (log_.opCode != 2 || log_.data.length < 64) return;
            // Decode skip as uint256: abi-decoding a bool reverts on values other than 0/1.
            (uint256 skip, uint256 originTimestamp) = abi.decode(log_.data, (uint256, uint256));
            if (skip != 0) {
                emit Skipped(log_.txHash, log_.chainId, log_.topic1, SKIP_FLAG);
                return;
            }
            _relay(log_, log_.topic1, originTimestamp);
        } else if (topic0 == SWAP_TOPIC0) {
            // Swap(PoolId indexed id, address indexed sender, int128, int128, uint160 sqrtPriceX96, ...): LOG3
            if (log_.opCode != 3 || log_.topic1 != poolId || log_.data.length < 96) return;
            (,, uint256 sqrtPriceX96) = abi.decode(log_.data, (uint256, uint256, uint256));
            _relay(log_, sqrtPriceX96, 0);
        }
        // anything else: fall through (never revert as a filter)
    }

    function _relay(LogRecord memory log_, uint256 n, uint256 originTimestamp) internal {
        address r = receiver;
        if (r == address(0)) {
            emit Skipped(log_.txHash, log_.chainId, n, SKIP_NO_RECEIVER);
            return;
        }
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: BASE_SEPOLIA,
                recipient: r,
                gasLimit: callbackGasLimit,
                payload: abi.encodeWithSignature(
                    "onPing(address,uint256,uint256,uint256,uint256,uint256)",
                    address(0), // overwritten by the network with this contract's address
                    n,
                    log_.chainId,
                    log_.blockNumber,
                    log_.txHash,
                    originTimestamp
                )
            })
        );
        emit Relayed(log_.txHash, log_.chainId, n);
    }

    /// @notice Owner-only: set the Base Sepolia PingReceiver (deploy order: this → receiver → setReceiver).
    function setReceiver(address receiver_) external onlyOwner {
        receiver = receiver_;
        emit ReceiverSet(receiver_);
    }

    /// @notice Pays any debt owed to the system contract from this contract's balance.
    function coverDebt() external {
        _coverDebt();
    }
}

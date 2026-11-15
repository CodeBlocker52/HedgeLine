// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title PingOrigin (M1 spike)
/// @notice Origin contract for the M1 hello loop. Same bytecode and CREATE2 address on Base Sepolia and Unichain Sepolia.
contract PingOrigin {
    /// @param n caller-chosen sequence number (indexed => topic1)
    /// @param skip when true the reactive contract must NOT request a callback
    /// @param timestamp origin block.timestamp, carried to the destination for latency measurement
    event Ping(uint256 indexed n, bool skip, uint256 timestamp);

    function ping(uint256 n, bool skip) external {
        emit Ping(n, skip, block.timestamp);
    }
}

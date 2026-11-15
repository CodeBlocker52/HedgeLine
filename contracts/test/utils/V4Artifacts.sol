// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Compiles v4-core's PoolManager (pinned =0.8.26) into out/ so ^0.8.29 tests can deploy it with
// deployCode("PoolManager.sol:PoolManager", abi.encode(owner)) without importing it directly.
import { PoolManager } from "v4-core/PoolManager.sol";

/// @dev Anchor so the file has its own AST node (silences forge's "AST source not found" warning).
abstract contract V4Artifacts { }

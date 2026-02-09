// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MoltStreetRegistry
 * @notice On-chain registry for MoltStreet tokens. Handles IP protection, ticker reservation,
 *         and creator claims.
 * @dev Standalone contract deployed before Factory. Factory calls into Registry during deployment.
 *
 * TODO: Implementation pending. See docs/CONTRACTS.md for full specification.
 *
 * Key mappings:
 * - ticker → token address
 * - token → creator address
 * - creator → tokens[]
 * - ticker → reservation expiry
 *
 * IP Protection features:
 * - Ticker reservation (24h, requires MOLTX stake)
 * - Duplicate detection (fuzzy matching off-chain, uniqueness on-chain)
 * - Creator claim (verified transfer of creator status)
 */

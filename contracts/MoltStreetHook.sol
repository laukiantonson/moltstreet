// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MoltStreetHook
 * @notice Uniswap v4 hook for MoltStreet pools. Handles fee distribution and anti-snipe.
 * @dev Implements afterSwap, beforeAddLiquidity, and afterInitialize hooks.
 *
 *      Fee distribution (governance-adjustable):
 *        40% → token creator (looked up via MoltStreetRegistry ledger)
 *        30% → MOLTX staker reward pool
 *        20% → MoltX treasury
 *        10% → MoltStreet operations
 *
 *      Anti-snipe (optional per pool):
 *        First N blocks: max buy size limited
 *        Configurable by creator at deploy time
 *
 *      Creator lookups use Registry.tokenToCreator() which is a materialized
 *      index of the append-only ledger. If creator transfers via claimCreator(),
 *      the new creator automatically receives fees — no hook update needed.
 *
 * TODO: Full implementation requires Uniswap v4 interfaces.
 *       See docs/CONTRACTS.md for specification.
 */

interface IMoltStreetRegistry {
    function tokenToCreator(address token) external view returns (address);
}

contract MoltStreetHook {

    // ──────────────────────────────────────────────
    // Types
    // ──────────────────────────────────────────────

    struct FeeConfig {
        uint16 creatorBps;     // basis points (default 4000 = 40%)
        uint16 stakerBps;      // default 3000 = 30%
        uint16 treasuryBps;    // default 2000 = 20%
        uint16 operationsBps;  // default 1000 = 10%
    }

    struct PoolConfig {
        bool antiSnipeEnabled;
        uint256 antiSnipeBlocks;
        uint256 antiSnipeMaxBuy;
        uint256 deployBlock;
    }

    // ──────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────

    IMoltStreetRegistry public registry;
    address public owner;
    address public stakerRewardPool;
    address public treasury;
    address public operations;

    FeeConfig public feeConfig;
    mapping(address => PoolConfig) public poolConfigs; // pool → config

    // Fee accounting
    mapping(address => uint256) public creatorFeesAccrued;   // creator → ETH
    uint256 public stakerFeesAccrued;
    uint256 public treasuryFeesAccrued;
    uint256 public operationsFeesAccrued;

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event FeeDistributed(
        address indexed pool,
        address indexed token,
        address indexed creator,
        uint256 totalFee,
        uint256 creatorShare,
        uint256 stakerShare,
        uint256 treasuryShare,
        uint256 operationsShare
    );

    event AntiSnipeBlocked(
        address indexed pool,
        address indexed buyer,
        uint256 attemptedAmount,
        uint256 maxAllowed
    );

    event FeeConfigUpdated(FeeConfig newConfig);
    event PoolRegistered(address indexed pool, PoolConfig config);

    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error Unauthorized();
    error InvalidFeeConfig();
    error AntiSnipeLimitExceeded(uint256 attempted, uint256 max);

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    constructor(
        address _registry,
        address _stakerRewardPool,
        address _treasury,
        address _operations
    ) {
        owner = msg.sender;
        registry = IMoltStreetRegistry(_registry);
        stakerRewardPool = _stakerRewardPool;
        treasury = _treasury;
        operations = _operations;

        // Default fee config
        feeConfig = FeeConfig({
            creatorBps: 4000,
            stakerBps: 3000,
            treasuryBps: 2000,
            operationsBps: 1000
        });
    }

    // ──────────────────────────────────────────────
    // Hook: afterInitialize (pool registration)
    // ──────────────────────────────────────────────

    /**
     * @notice Called after a new pool is initialized. Registers pool config.
     * @dev In production, this is called by Uniswap v4 PoolManager.
     */
    function registerPool(
        address pool,
        address token,
        bool antiSnipeEnabled,
        uint256 antiSnipeBlocks,
        uint256 antiSnipeMaxBuy
    ) external {
        // In production: verify caller is PoolManager
        poolConfigs[pool] = PoolConfig({
            antiSnipeEnabled: antiSnipeEnabled,
            antiSnipeBlocks: antiSnipeBlocks,
            antiSnipeMaxBuy: antiSnipeMaxBuy,
            deployBlock: block.number
        });

        emit PoolRegistered(pool, poolConfigs[pool]);
    }

    // ──────────────────────────────────────────────
    // Hook: afterSwap (fee distribution)
    // ──────────────────────────────────────────────

    /**
     * @notice Distribute fees after a swap.
     * @dev Creator address is resolved from Registry's materialized index.
     *      The Registry's append-only ledger ensures creator transfers are
     *      automatically reflected here without any hook update.
     * @param pool The pool address
     * @param token The token being traded
     * @param feeAmount The fee amount in ETH/WETH to distribute
     */
    function distributeFees(
        address pool,
        address token,
        uint256 feeAmount
    ) external {
        // Resolve creator from Registry (reads materialized index)
        address creator = registry.tokenToCreator(token);

        // Calculate shares
        uint256 creatorShare = (feeAmount * feeConfig.creatorBps) / 10000;
        uint256 stakerShare = (feeAmount * feeConfig.stakerBps) / 10000;
        uint256 treasuryShare = (feeAmount * feeConfig.treasuryBps) / 10000;
        uint256 operationsShare = feeAmount - creatorShare - stakerShare - treasuryShare;

        // Accrue fees
        creatorFeesAccrued[creator] += creatorShare;
        stakerFeesAccrued += stakerShare;
        treasuryFeesAccrued += treasuryShare;
        operationsFeesAccrued += operationsShare;

        // TODO: Transfer fees to respective addresses
        // payable(creator).transfer(creatorShare);
        // payable(stakerRewardPool).transfer(stakerShare);
        // payable(treasury).transfer(treasuryShare);
        // payable(operations).transfer(operationsShare);

        emit FeeDistributed(
            pool, token, creator, feeAmount,
            creatorShare, stakerShare, treasuryShare, operationsShare
        );
    }

    // ──────────────────────────────────────────────
    // Hook: beforeAddLiquidity / beforeSwap (anti-snipe)
    // ──────────────────────────────────────────────

    /**
     * @notice Check anti-snipe restrictions before a buy.
     * @param pool The pool address
     * @param buyer The buyer address
     * @param amount The buy amount
     */
    function checkAntiSnipe(
        address pool,
        address buyer,
        uint256 amount
    ) external view {
        PoolConfig memory config = poolConfigs[pool];

        if (!config.antiSnipeEnabled) return;

        // Check if still in anti-snipe window
        if (block.number <= config.deployBlock + config.antiSnipeBlocks) {
            if (amount > config.antiSnipeMaxBuy) {
                revert AntiSnipeLimitExceeded(amount, config.antiSnipeMaxBuy);
            }
        }
    }

    // ──────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────

    function setFeeConfig(FeeConfig calldata _config) external {
        if (msg.sender != owner) revert Unauthorized();
        if (_config.creatorBps + _config.stakerBps + _config.treasuryBps + _config.operationsBps != 10000) {
            revert InvalidFeeConfig();
        }
        feeConfig = _config;
        emit FeeConfigUpdated(_config);
    }

    function setAddresses(
        address _stakerRewardPool,
        address _treasury,
        address _operations
    ) external {
        if (msg.sender != owner) revert Unauthorized();
        stakerRewardPool = _stakerRewardPool;
        treasury = _treasury;
        operations = _operations;
    }

    function transferOwnership(address _newOwner) external {
        if (msg.sender != owner) revert Unauthorized();
        owner = _newOwner;
    }
}

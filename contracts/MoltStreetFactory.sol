// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MoltStreetRegistry} from "./MoltStreetRegistry.sol";

/**
 * @title MoltStreetFactory
 * @notice Deploys ERC-20 tokens and registers them in MoltStreetRegistry.
 * @dev All token deployments route through the Registry's append-only ledger.
 *      Factory → Registry.registerToken() → _appendEntry() → immutable record.
 *
 *      In production, this integrates with clanker for Uniswap v4 pool creation.
 *      The Factory wraps clanker's deploy engine with MoltStreet's IP protection
 *      and ledger tracking.
 *
 *      Deploy flow:
 *        1. Validate ticker via Registry.isTickerAvailable()
 *        2. Deploy minimal ERC-20 (CREATE2 for deterministic address)
 *        3. Create Uniswap v4 pool via clanker bridge
 *        4. Register in MoltStreetRegistry (creates TOKEN_REGISTERED ledger entry)
 *        5. Emit deployment event for off-chain indexing
 */
contract MoltStreetFactory {

    // ──────────────────────────────────────────────
    // Types
    // ──────────────────────────────────────────────

    struct DeployParams {
        string name;
        string ticker;
        uint256 initialSupply;
        address creator;
        bytes32 metadataHash;   // IPFS hash of token metadata
        bool antiSnipe;
        uint256 antiSnipeBlocks;
        uint256 antiSnipeMaxBuy;
    }

    struct DeployResult {
        address token;
        address pool;
        uint256 registryEntryId;
    }

    // ──────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────

    MoltStreetRegistry public registry;
    address public owner;
    address public hookAddress;      // MoltStreetHook for Uniswap v4
    address public poolManager;      // Uniswap v4 PoolManager on Base

    // Deploy tracking (lightweight — details live in Registry ledger)
    uint256 public totalDeployments;
    mapping(address => bool) public isDeployedToken;

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event TokenDeployed(
        address indexed token,
        string ticker,
        address indexed creator,
        address pool,
        uint256 indexed registryEntryId,
        uint256 initialSupply,
        bytes32 metadataHash
    );

    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error Unauthorized();
    error TickerNotAvailable(string ticker);
    error InvalidParams();
    error DeployFailed();

    // ──────────────────────────────────────────────
    // Modifiers
    // ──────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    constructor(
        address _registry,
        address _poolManager,
        address _hookAddress
    ) {
        owner = msg.sender;
        registry = MoltStreetRegistry(_registry);
        poolManager = _poolManager;
        hookAddress = _hookAddress;
    }

    // ──────────────────────────────────────────────
    // Core: Deploy Token
    // ──────────────────────────────────────────────

    /**
     * @notice Deploy a new ERC-20 token with Uniswap v4 pool.
     * @dev All state changes route through Registry ledger.
     *      The ledger entry created by Registry.registerToken() is the
     *      canonical record of this deployment.
     * @param params Deployment parameters
     * @return result Deploy result with token address, pool, and ledger entry ID
     */
    function deployToken(
        DeployParams calldata params
    ) external returns (DeployResult memory result) {
        // Validate
        if (bytes(params.ticker).length == 0 || bytes(params.ticker).length > 10) {
            revert InvalidParams();
        }
        if (params.creator == address(0)) revert InvalidParams();
        if (params.initialSupply == 0) revert InvalidParams();

        // Check ticker availability via Registry
        if (!registry.isTickerAvailable(params.ticker)) {
            revert TickerNotAvailable(params.ticker);
        }

        // Step 1: Deploy ERC-20 contract
        // In production: use CREATE2 for deterministic address
        // For now: deploy minimal MoltStreetToken
        address token = _deployERC20(
            params.name,
            params.ticker,
            params.initialSupply,
            params.creator
        );

        // Step 2: Create Uniswap v4 pool via clanker bridge
        // In production: call clanker API or direct PoolManager
        address pool = _createPool(token, params.antiSnipe, params.antiSnipeBlocks, params.antiSnipeMaxBuy);

        // Step 3: Register in MoltStreetRegistry (creates ledger entry)
        // This is the canonical state mutation — everything else is derived
        registry.registerToken(
            params.ticker,
            token,
            params.creator,
            params.metadataHash
        );

        // Step 4: Update local tracking
        totalDeployments++;
        isDeployedToken[token] = true;

        // Get the registry entry ID (latest entry)
        uint256 registryEntryId = registry.ledgerLength() - 1;

        result = DeployResult({
            token: token,
            pool: pool,
            registryEntryId: registryEntryId
        });

        emit TokenDeployed(
            token,
            params.ticker,
            params.creator,
            pool,
            registryEntryId,
            params.initialSupply,
            params.metadataHash
        );
    }

    // ──────────────────────────────────────────────
    // Internal: ERC-20 deployment
    // ──────────────────────────────────────────────

    /**
     * @dev Deploy a minimal ERC-20 token.
     *      Production: use CREATE2 + minimal proxy or full ERC-20 with fixed supply.
     *      MVP: placeholder that returns a precomputed address.
     */
    function _deployERC20(
        string calldata name,
        string calldata ticker,
        uint256 initialSupply,
        address creator
    ) internal returns (address token) {
        // TODO: Production implementation
        // bytes32 salt = keccak256(abi.encodePacked(ticker, creator, block.timestamp));
        // token = address(new MoltStreetToken{salt: salt}(name, ticker, initialSupply, creator));
        // if (token == address(0)) revert DeployFailed();

        // Placeholder: compute deterministic address for testing
        token = address(uint160(uint256(keccak256(abi.encodePacked(
            name, ticker, initialSupply, creator, block.timestamp
        )))));
    }

    /**
     * @dev Create Uniswap v4 pool with MoltStreetHook.
     *      Production: call PoolManager.initialize() with hook address.
     *      MVP: placeholder.
     */
    function _createPool(
        address token,
        bool antiSnipe,
        uint256 antiSnipeBlocks,
        uint256 antiSnipeMaxBuy
    ) internal returns (address pool) {
        // TODO: Production implementation
        // PoolKey memory key = PoolKey({
        //     currency0: Currency.wrap(token < WETH ? token : WETH),
        //     currency1: Currency.wrap(token < WETH ? WETH : token),
        //     fee: 3000,
        //     tickSpacing: 60,
        //     hooks: IHooks(hookAddress)
        // });
        // poolManager.initialize(key, SQRT_PRICE_1_1, "");

        // Placeholder
        pool = address(uint160(uint256(keccak256(abi.encodePacked(
            token, hookAddress, block.timestamp
        )))));
    }

    // ──────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────

    function setRegistry(address _registry) external onlyOwner {
        registry = MoltStreetRegistry(_registry);
    }

    function setHookAddress(address _hook) external onlyOwner {
        hookAddress = _hook;
    }

    function setPoolManager(address _pm) external onlyOwner {
        poolManager = _pm;
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert InvalidParams();
        owner = _newOwner;
    }
}

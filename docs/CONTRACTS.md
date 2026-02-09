# Smart Contract Specifications

## Overview

All contracts deploy on Base (Chain ID: 8453). Development uses Foundry. Contracts interact with Uniswap v4 PoolManager deployed on Base.

## MoltStreetFactory

**Purpose:** Deploy ERC-20 tokens and create Uniswap v4 pools in a single transaction.

```solidity
// Key functions
function deployToken(
    string memory name,
    string memory ticker,
    uint256 initialSupply,
    address creator,
    bytes32 metadataHash  // IPFS hash of token metadata (image, description, socials)
) external returns (address token, PoolId poolId);

function getTokenByTicker(string memory ticker) external view returns (address);
function getTokensByCreator(address creator) external view returns (address[] memory);
```

**Deploy flow:**
1. Check ticker not taken (MoltStreetRegistry)
2. Deploy minimal ERC-20 (OpenZeppelin base, no mint function post-deploy)
3. Call Uniswap v4 PoolManager.initialize() with token/WETH pair
4. Add initial concentrated LP position around starting price
5. Register in MoltStreetRegistry
6. Emit `TokenDeployed(address token, string ticker, address creator, PoolId poolId)`

**Considerations:**
- Initial supply: fixed at deploy time, no inflation
- Starting price: configurable by creator or default (e.g., ~$0.001)
- LP range: concentrated ±50% around starting price (adjustable)
- Gas optimization: use CREATE2 for deterministic addresses

## MoltStreetHook

**Purpose:** Uniswap v4 hook that intercepts swaps on MoltStreet pools to distribute fees.

```solidity
// Hook permissions needed:
// - afterSwap (fee collection)
// - beforeAddLiquidity (anti-snipe, optional)
// - afterInitialize (pool registration)

function afterSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
) external override returns (bytes4, int128) {
    // Calculate fee from swap amount
    // Distribute to: creator, MOLTX stakers, treasury, operations
    // Fee percentages read from governance contract
}
```

**Fee distribution (default, governance-adjustable):**
- 40% → creator reward address
- 30% → MOLTX staker reward pool
- 20% → MoltX treasury
- 10% → MoltStreet operations multisig

**Anti-snipe (optional, per-pool):**
- First N blocks after pool creation: max buy size limited
- Prevents bot sniping on new token launches
- Creator can opt in/out at deploy time

## MoltStreetRegistry

**Purpose:** On-chain registry for IP protection and token discovery.

```solidity
mapping(bytes32 => address) public tickerToToken;      // keccak256(ticker) → token
mapping(address => address) public tokenToCreator;       // token → creator
mapping(address => address[]) public creatorToTokens;    // creator → tokens[]
mapping(bytes32 => uint256) public tickerReservedUntil;  // ticker → reservation expiry

function reserveTicker(string memory ticker) external;   // 24h reservation
function claimCreator(address token) external;           // creator claim with verification
function isTickerAvailable(string memory ticker) external view returns (bool);
```

**IP Protection:**
- `reserveTicker`: locks a ticker for 24 hours (requires small MOLTX stake)
- `claimCreator`: transfers creator status (requires off-chain verification via oracle/multisig)
- Ticker availability checked at deploy time by Factory

## MoltStreetGovernor (or MoltCity integration)

**Purpose:** Governance over protocol parameters.

**Governable parameters:**
- Fee split percentages (creator/stakers/treasury/operations)
- Anti-snipe settings (block delay, max buy)
- Minimum stake for ticker reservation
- Listing policies (auto-list vs manual review threshold)

**Options:**
1. **Own Governor contract** — OpenZeppelin Governor with MOLTX voting
2. **MoltCity integration** — proposals and votes happen through MoltCity governance, parameters updated via multisig execution

Recommendation: Start with multisig-controlled parameters, migrate to MoltCity governance once that infrastructure matures.

## Deployment Order

1. MoltStreetRegistry (standalone)
2. MoltStreetHook (needs Uniswap v4 PoolManager address)
3. MoltStreetFactory (needs Registry + Hook + PoolManager addresses)
4. Governance/multisig setup
5. Testnet validation
6. Mainnet deployment

## Gas Estimates (rough)

- Token deploy + pool creation: ~500K-800K gas (~$0.50-1.00 on Base)
- Trade (swap): ~150K-250K gas (~$0.15-0.25 on Base)
- Ticker reservation: ~50K gas (~$0.05 on Base)

Base L2 gas costs make this viable for casual users. On L1 Ethereum, this would be prohibitively expensive.

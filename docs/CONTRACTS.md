# Smart Contract Specifications

## Overview

All contracts deploy on Base (Chain ID: 8453). Development uses Foundry. Contracts interact with Uniswap v4 PoolManager deployed on Base.

## Ledger Architecture (Refactored from C1726 Audit)

**Previous model (HYBRID):** Counter-based mappings as source of truth, decorative event logs for tracking. ~10 mutation sites scattered across contracts with no unified audit trail.

**Current model (FULL LEDGER):** Append-only `LedgerEntry[]` in MoltStreetRegistry is the canonical source of truth. Every state mutation creates an immutable entry. Mappings (`tickerToToken`, `tokenToCreator`, etc.) serve as **materialized indexes** for gas-efficient reads — they are derived from the ledger, not the other way around.

### Why Full Ledger?

1. **Auditability** — Every state change has a timestamp, block number, actor, and type
2. **History** — Can reconstruct any ticker/token/creator state at any point in time
3. **Integrity** — Append-only = no silent overwrites, no counter drift
4. **Off-chain sync** — Subgraphs/indexers can replay the ledger to rebuild state
5. **Dispute resolution** — Creator transfers, ticker claims all have provenance

### Ledger Entry Types

| Type | When Created | Key Fields |
|------|-------------|------------|
| `TICKER_RESERVED` | User reserves a ticker | tickerHash, actor (reserver) |
| `TOKEN_REGISTERED` | Factory deploys a new token | tickerHash, token, beneficiary (creator) |
| `CREATOR_CLAIMED` | Creator status transferred | token, actor (old creator), beneficiary (new) |
| `TICKER_RELEASED` | Reservation expired/cancelled | tickerHash, actor, beneficiary (stake return) |

### Mutation Flow

All 5 mutation functions route through `_appendEntry()`:

```
reserveTicker()           → _appendEntry(TICKER_RESERVED)
releaseReservation()      → _appendEntry(TICKER_RELEASED)
releaseExpiredReservation()→ _appendEntry(TICKER_RELEASED)
registerToken()           → _appendEntry(TOKEN_REGISTERED)
claimCreator()            → _appendEntry(CREATOR_CLAIMED)
```

### Reverse Indexes

For efficient queries, the ledger maintains three reverse index mappings:
- `_tickerLedgerEntries[tickerHash]` → entry IDs involving this ticker
- `_tokenLedgerEntries[token]` → entry IDs involving this token
- `_actorLedgerEntries[actor]` → entry IDs for actions by this address

## MoltStreetFactory

**Purpose:** Deploy ERC-20 tokens and create Uniswap v4 pools in a single transaction.

```solidity
struct DeployParams {
    string name;
    string ticker;
    uint256 initialSupply;
    address creator;
    bytes32 metadataHash;
    bool antiSnipe;
    uint256 antiSnipeBlocks;
    uint256 antiSnipeMaxBuy;
}

function deployToken(DeployParams calldata params) external returns (DeployResult memory);
```

**Deploy flow:**
1. Validate ticker length and creator address
2. Check ticker availability via Registry.isTickerAvailable()
3. Deploy minimal ERC-20 (CREATE2 for deterministic address)
4. Create Uniswap v4 pool via clanker bridge / PoolManager
5. Register in MoltStreetRegistry → creates `TOKEN_REGISTERED` ledger entry
6. Emit `TokenDeployed` event with registry entry ID for cross-referencing

**Key:** The Factory's `deployToken()` is NOT the source of truth — the ledger entry created by `Registry.registerToken()` is.

## MoltStreetHook

**Purpose:** Uniswap v4 hook that intercepts swaps on MoltStreet pools to distribute fees.

```solidity
function distributeFees(address pool, address token, uint256 feeAmount) external;
function checkAntiSnipe(address pool, address buyer, uint256 amount) external view;
```

**Fee distribution (default, governance-adjustable):**
- 40% → creator reward address (resolved from Registry's materialized index)
- 30% → MOLTX staker reward pool
- 20% → MoltX treasury
- 10% → MoltStreet operations multisig

**Ledger integration:** Creator address is resolved via `Registry.tokenToCreator()` which reads the materialized index. When a creator transfer occurs (`claimCreator()`), the ledger records it and the index updates — the Hook automatically distributes to the new creator without any contract upgrade.

**Anti-snipe (optional, per-pool):**
- First N blocks after pool creation: max buy size limited
- Prevents bot sniping on new token launches
- Creator can opt in/out at deploy time

## MoltStreetRegistry

**Purpose:** Full append-only ledger for IP protection and token provenance.

```solidity
// Ledger (source of truth)
LedgerEntry[] public ledger;

// Materialized indexes (derived from ledger)
mapping(bytes32 => address) public tickerToToken;
mapping(address => address) public tokenToCreator;
mapping(address => address[]) internal _creatorToTokens;
mapping(bytes32 => uint256) public tickerReservedUntil;
mapping(bytes32 => address) public tickerReservedBy;

// Mutations (all route through _appendEntry)
function reserveTicker(string calldata ticker) external;
function releaseReservation(string calldata ticker) external;
function releaseExpiredReservation(string calldata ticker) external;
function registerToken(string calldata ticker, address token, address creator, bytes32 metadataHash) external;
function claimCreator(address token, address newCreator) external;

// Views
function isTickerAvailable(string calldata ticker) external view returns (bool);
function getTokensByCreator(address creator) external view returns (address[] memory);
function getLedgerEntries(uint256 start, uint256 count) external view returns (LedgerEntry[] memory);
function getTickerHistory(string calldata ticker) external view returns (uint256[] memory);
function getTokenHistory(address token) external view returns (uint256[] memory);
function getActorHistory(address actor) external view returns (uint256[] memory);
```

**IP Protection:**
- `reserveTicker`: Locks a ticker for 24 hours (requires MOLTX stake)
- `claimCreator`: Transfers creator status (requires current creator or owner)
- Ticker availability checked at deploy time by Factory
- All actions recorded in ledger with full provenance

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

1. MoltStreetRegistry (standalone, needs MOLTX token address)
2. MoltStreetHook (needs Registry + Uniswap v4 PoolManager address)
3. MoltStreetFactory (needs Registry + Hook + PoolManager addresses)
4. `Registry.setFactory(factoryAddress)` — authorize Factory to register tokens
5. Governance/multisig setup
6. Testnet validation
7. Mainnet deployment

## Gas Estimates (rough)

- Token deploy + pool creation + ledger write: ~600K-900K gas (~$0.60-1.00 on Base)
- Trade (swap) + fee distribution: ~150K-250K gas (~$0.15-0.25 on Base)
- Ticker reservation + ledger write: ~70K gas (~$0.07 on Base)
- Creator transfer + ledger write: ~80K gas (~$0.08 on Base)

Base L2 gas costs make this viable for casual users. The ledger writes add ~20K gas per mutation vs the old counter-only model — negligible on L2.

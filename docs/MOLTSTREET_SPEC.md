# MoltStreet Token Launchpad v1 -- Build Specification

## Overview

Build a **simplified token launchpad** on Uniswap V4 that allows whitelisted deployers (bots) to deploy ERC20 tokens, automatically create a Uniswap V4 liquidity pool with a static fee, and manage fee distribution. MoltStreet takes a configurable percentage (0%--40%) of all trading fees, updatable by the owner and read live on every swap. The rest is split among user-configured recipients.

The factory contract is **upgradeable** (UUPS proxy pattern), deployed initially with an empty implementation and then upgraded to the real implementation.

---

## Tech Stack

- **Solidity ^0.8.28** with Foundry
- **Uniswap V4** (v4-core + v4-periphery) for pool creation and hooks
- **OpenZeppelin Contracts** for ERC20, access control, security utilities, and UUPS proxy
- **EVM target**: Cancun (for transient storage support required by Uniswap V4)
- **Optimizer**: enabled, viaIR: true

---

## Architecture Overview

```
                        ┌─────────────────────┐
                        │    ERC1967 Proxy     │
                        │  (permanent address) │
                        └──────────┬──────────┘
                                   │ delegatecall
                                   v
┌──────────────────────────────────────────────────────────┐
│              MoltStreetFactory (Implementation)          │
│         (Upgradeable via UUPS, only whitelisted          │
│          deployers can deploy tokens)                    │
│                                                          │
│  deployToken(DeploymentConfig) → token address           │
│                                                          │
│  1. Deploy MoltStreetToken (ERC20)                       │
│  2. Split supply: LP (≥15% or 100%) + Owner + Airdrop   │
│  3. Initialize Uniswap V4 pool via Hook                  │
│  4. Place liquidity via LP Locker                        │
│  5. Execute airdrop (if configured) -- direct transfer   │
│  6. Send remaining tokens to owner                       │
└──────────┬──────────┬──────────┬─────────────────────────┘
           │          │          │
           v          v          v
    ┌──────────┐ ┌─────────┐ ┌────────────┐
    │MoltStreet│ │MoltStreet│ │ MoltStreet │
    │  Token   │ │  Hook    │ │  Airdrop   │
    │ (ERC20)  │ │(Static   │ │ (Direct    │
    │          │ │  Fee)    │ │  Transfer) │
    └──────────┘ └────┬────┘ └────────────┘
                      │
                      v
               ┌──────────────┐     ┌────────────────┐
               │  MoltStreet  │────>│  MoltStreet    │
               │  LpLocker    │     │  FeeVault      │
               │              │     │ (accumulates &  │
               │              │     │  distributes)   │
               └──────────────┘     └────────────────┘
```

---

## Contracts Summary

| # | Contract | Purpose |
|---|----------|---------|
| 1 | `MoltStreetToken` | ERC20 token (Permit + Votes + Burnable) |
| 2 | `MoltStreetFactory` | Upgradeable factory (UUPS proxy), whitelisted deployer access |
| 3 | `MoltStreetHook` | Uniswap V4 hook with static fees, reads protocol fee live |
| 4 | `MoltStreetFeeVault` | Fee accumulation & permissionless claiming |
| 5 | `MoltStreetLpLocker` | Permanent LP locking, fee collection & routing |
| 6 | `MoltStreetAirdrop` | Direct-transfer airdrop to address arrays (no merkle) |

---

## Contract #1: MoltStreetToken

An ERC20 token deployed for every launch.

### Inherits
- `ERC20` -- base token
- `ERC20Permit` -- gasless approvals via EIP-2612 signatures
- `ERC20Votes` -- on-chain governance / delegation support (EIP-5805)
- `ERC20Burnable` -- anyone can burn their own tokens

### Constants
- Fixed supply: **1 billion tokens** (1_000_000_000e18)

### Storage
```solidity
address private immutable _initialOwner;  // set at deploy, never changes
address private _owner;                    // current owner (transferable)
string private _image;                     // token image URL
string private _metadata;                  // token metadata string
string private _context;                   // immutable context (who deployed, why, etc.)
```

### Constructor -- takes a struct

```solidity
struct TokenParams {
    string name;
    string symbol;
    uint256 maxSupply;
    address owner;          // initial owner of the token
    string image;
    string metadata;
    string context;
}

constructor(TokenParams memory params) ERC20(params.name, params.symbol) ERC20Permit(params.name) {
    _initialOwner = params.owner;
    _owner = params.owner;
    _image = params.image;
    _metadata = params.metadata;
    _context = params.context;

    // Always mint full supply to msg.sender (the factory)
    _mint(msg.sender, params.maxSupply);
}
```

### Token Owner Functions
```solidity
// Transfer ownership
function updateOwner(address newOwner) external; // only current _owner

// Update token image URL
function updateImage(string memory image_) external; // only _owner

// Update token metadata
function updateMetadata(string memory metadata_) external; // only _owner
```

All of these revert with `NotOwner()` if called by anyone other than `_owner`.

### View Functions
```solidity
function owner() external view returns (address);
function initialOwner() external view returns (address);
function imageUrl() external view returns (string memory);
function metadata() external view returns (string memory);
function context() external view returns (string memory);

// Returns all data in one call (gas-efficient for frontends)
function allData() external view returns (
    address initialOwner_,
    address owner_,
    string memory image,
    string memory metadata,
    string memory context
);
```

### ERC20 Overrides
```solidity
// Required override for ERC20 + ERC20Votes
function _update(address from, address to, uint256 value)
    internal override(ERC20, ERC20Votes);

// Required override for ERC20Permit + Nonces
function nonces(address owner_)
    public view override(ERC20Permit, Nonces) returns (uint256);
```

### Deployment
- Use **CREATE2** with a deployer-provided `salt` for deterministic addresses
- Full supply always minted to `msg.sender` (the factory) on deploy

### Events
```solidity
event UpdateImage(string image);
event UpdateMetadata(string metadata);
event UpdateOwner(address indexed oldOwner, address indexed newOwner);
```

### Errors
```solidity
error NotOwner();
```

---

## Contract #2: MoltStreetFactory (Upgradeable -- UUPS Proxy)

The main factory contract. Deployed behind an ERC1967 proxy using the UUPS pattern.

### Upgrade Strategy

1. Deploy an **empty implementation** contract (minimal contract that only has the UUPS upgrade logic)
2. Deploy the **ERC1967 proxy** pointing to the empty implementation
3. Deploy the **real MoltStreetFactory implementation**
4. Call `upgradeToAndCall()` on the proxy to switch to the real implementation and call `initialize()`

This allows the proxy address to exist before the real logic is ready, useful for pre-registering addresses in other contracts.

### Inherits
- `UUPSUpgradeable` (OpenZeppelin)
- `OwnableUpgradeable` (OpenZeppelin)
- `ReentrancyGuardUpgradeable` (OpenZeppelin)

### Access Control
- **Owner** (via OwnableUpgradeable): Full control -- can add/remove deployers, update protocol fee %, set fee recipient, pause/unpause, enable/disable modules, upgrade the implementation
- **Whitelisted Deployers**: Can call `deployToken()`. These are backend bots that deploy on behalf of users.

### Constants
```solidity
uint256 public constant TOKEN_SUPPLY = 1_000_000_000e18;    // 1B tokens
uint256 public constant BPS = 10_000;
uint16 public constant MIN_LP_BPS = 1_500;                   // minimum 15% to LP
uint16 public constant MAX_PROTOCOL_FEE_BPS = 4_000;         // max 40% protocol fee
```

### State
```solidity
bool public paused;                                           // pause/unpause deployments
address public moltstreetFeeRecipient;                        // where protocol fees go
uint16 public protocolFeeBps;                                 // MoltStreet's cut of LP fees (0-4000 BPS, live on every swap)

mapping(address => bool) public whitelistedDeployers;         // who can deploy
mapping(address => DeploymentInfo) public deployments;        // token => deployment info

// enabled modules (allowlists)
mapping(address => bool) public enabledHooks;
mapping(address => mapping(address => bool)) public enabledLockers;
```

### Initializer (replaces constructor for upgradeable)

```solidity
function initialize(address owner_, address feeRecipient_, uint16 protocolFeeBps_) external initializer {
    __Ownable_init(owner_);
    __ReentrancyGuard_init();
    __UUPSUpgradeable_init();

    moltstreetFeeRecipient = feeRecipient_;
    protocolFeeBps = protocolFeeBps_;
    paused = true; // start paused, owner must explicitly unpause
}

function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
```

### Configuration Structs

```solidity
struct TokenConfig {
    address tokenOwner;           // owner of the deployed token (_owner / _initialOwner)
    string name;
    string symbol;
    bytes32 salt;                 // for CREATE2 deterministic deployment
    string image;
    string metadata;
    string context;               // immutable context (who deployed it, etc.)
}

struct PoolConfig {
    address hook;                 // must be an enabled hook
    address pairedToken;          // the other token in the pair (usually WETH)
    int24 startingTick;           // initial price tick (as if deployed token is token0)
    int24 tickSpacing;            // tick spacing for the pool
    bytes hookData;               // hook-specific config (e.g., static fee values)
}

struct LiquidityConfig {
    address locker;               // LP locker contract address
    uint16 lpBps;                 // basis points of supply for LP (1500-10000)
    int24[] tickLower;            // lower ticks for LP positions (up to 7)
    int24[] tickUpper;            // upper ticks for LP positions (up to 7)
    uint16[] positionBps;         // how to split LP supply across positions (must sum to 10000)
}

struct FeeDistributionConfig {
    address[] recipients;         // fee recipient addresses (up to 5)
    uint16[] recipientBps;        // each recipient's share of the USER portion (must sum to 10000)
    address[] recipientAdmins;    // who can update each recipient address later
}

struct AirdropConfig {
    bool enabled;                 // whether to do an airdrop
    uint16 airdropBps;            // portion of total supply for airdrop (in BPS)
    address[] recipients;         // airdrop recipient addresses
    uint256[] amounts;            // amount each recipient gets (must sum to airdropBps% of total supply)
}

struct DeploymentConfig {
    TokenConfig tokenConfig;
    PoolConfig poolConfig;
    LiquidityConfig liquidityConfig;
    FeeDistributionConfig feeConfig;
    AirdropConfig airdropConfig;
}

struct DeploymentInfo {
    address token;
    address hook;
    address locker;
}
```

### Supply Split Logic

```
Total Supply = 1 billion tokens (1_000_000_000e18)
    │
    ├── LP Portion (≥ 15%, up to 100%, set via liquidityConfig.lpBps)
    │       → sent to LP Locker → minted as Uniswap V4 LP positions
    │
    ├── Airdrop Portion (optional, set via airdropConfig.airdropBps)
    │       → sent DIRECTLY to each address in recipients[] array
    │       → amounts[] specifies how much each address gets
    │       → no claiming needed, tokens land in wallets immediately
    │
    └── Owner Portion (remainder = 100% - LP% - Airdrop%)
            → sent directly to tokenConfig.tokenOwner wallet
            → can be 0% if LP + Airdrop = 100%
```

**Validation rules:**
- `liquidityConfig.lpBps >= 1500` (at least 15% to LP)
- `liquidityConfig.lpBps <= 10000` (can be 100% to LP)
- `liquidityConfig.lpBps + airdropConfig.airdropBps <= 10000`
- If `airdropConfig.enabled == false`, `airdropBps` must be 0 and arrays must be empty
- If `airdropConfig.enabled == true`:
  - `recipients.length == amounts.length`
  - `recipients.length > 0`
  - `sum(amounts) == airdropBps * TOKEN_SUPPLY / BPS`
  - No zero addresses in recipients
  - No zero amounts
- Owner portion = `10000 - lpBps - airdropBps` (can be 0)
- If lpBps == 10000, no airdrop and no owner allocation (100% to LP)

### Core Function: `deployToken()`

```solidity
function deployToken(DeploymentConfig calldata config)
    external
    nonReentrant
    returns (address tokenAddress)
```

**Access**: Only whitelisted deployers, only when not paused.

**Flow:**
1. Validate caller is a whitelisted deployer, factory is not paused
2. Validate supply split (LP ≥ 15%, LP + Airdrop ≤ 100%, airdrop arrays valid)
3. Deploy `MoltStreetToken` via CREATE2 (1B supply minted to factory)
4. Initialize Uniswap V4 pool via the Hook
5. Approve and send LP portion to the LP Locker → locker mints LP positions
6. If airdrop enabled → loop through recipients[] and transfer amounts[] directly
7. If ownerBps > 0 → send remaining tokens directly to `tokenConfig.tokenOwner`
8. Store deployment info, emit `TokenDeployed` event

### Owner Functions

```solidity
// Deployer management
function setDeployer(address deployer, bool enabled) external onlyOwner;

// Pause / unpause new deployments
function setPaused(bool paused_) external onlyOwner;

// Protocol fee configuration -- LIVE on every swap, range 0-4000 BPS (0%-40%)
function setProtocolFeeBps(uint16 feeBps) external onlyOwner;
function setMoltStreetFeeRecipient(address recipient) external onlyOwner;

// Module allowlisting
function setHook(address hook, bool enabled) external onlyOwner;
function setLocker(address locker, address hook, bool enabled) external onlyOwner;

// Claim accumulated protocol fees from the hook
function claimProtocolFees(address token) external onlyOwner;
```

---

## Contract #3: MoltStreetHook (Static Fee)

A Uniswap V4 hook that attaches to every pool created by the factory. Static fees only.

### Responsibilities

1. **Set LP fees**: Apply a static fee on every swap (configurable per pool at deployment)
2. **Collect protocol fee**: On every swap, read `protocolFeeBps` **live from the factory** and take that % of LP fees in the paired token for MoltStreet
3. **Auto-collect LP fees**: After each swap, collect accrued LP fees from the pool and route them to the LP Locker, which deposits into the Fee Vault

### Hook Permissions (Uniswap V4 hook flags)
- `beforeInitialize` -- validate pool creation is from factory or allowed
- `afterSwap` -- collect fees, route to fee vault
- `beforeSwap` -- apply correct static fee (buy vs sell)

### Static Fee Config (per pool)

```solidity
struct PoolFeeConfig {
    uint24 buyFee;    // fee when buying the launched token (paired token is input)
    uint24 sellFee;   // fee when selling the launched token (launched token is input)
}
```

Passed via `poolConfig.hookData` as `abi.encode(PoolFeeConfig)`.

### Per-Pool Storage -- Single Struct Mapping

All pool-specific data is stored in ONE struct, accessed by a single `mapping(PoolId => PoolInfo)`:

```solidity
struct PoolInfo {
    address locker;              // which locker manages this pool's LP
    address token;               // the launched token address
    address pairedToken;         // the paired token address
    bool tokenIsToken0;          // whether the launched token is token0 in the pair
    uint24 buyFee;               // static fee for buys
    uint24 sellFee;              // static fee for sells
    bool initialized;            // whether this pool has been initialized
}

mapping(PoolId => PoolInfo) public pools;
```

### Protocol Fee -- Read Live From Factory

The hook does **NOT** store `protocolFeeBps` per pool. Instead, on every swap it reads the current value from the factory:

```solidity
// In afterSwap():
uint16 currentProtocolFeeBps = IMoltStreetFactory(factory).protocolFeeBps();
uint256 protocolFee = (totalLpFees * currentProtocolFeeBps) / BPS;
uint256 userFees = totalLpFees - protocolFee;
```

This means:
- Owner updates `protocolFeeBps` on the factory → **immediately affects ALL pools on the next swap**
- Can be set to 0% (no protocol fee) or up to 40% max
- No per-pool override -- global setting, single source of truth

### Fee Flow (on every swap)

```
Swap happens on Uniswap V4 Pool
    │
    afterSwap() hook fires
    │
    ├── Collect LP fees accrued from PREVIOUS swap (fees lag by 1 swap)
    │       │
    │       ├── Read factory.protocolFeeBps() LIVE
    │       │
    │       ├── protocolFeeBps% of LP fees (paired token) → held for MoltStreet
    │       │       (claimable by factory owner via claimProtocolFees)
    │       │
    │       └── remaining LP fees → sent to LP Locker → FeeVault
    │               → split among user-configured recipients by their BPS shares
    │
    └── Apply static fee for CURRENT swap (buyFee or sellFee depending on direction)
```

### Immutable References
```solidity
address public immutable factory;          // MoltStreetFactory proxy address
IPoolManager public immutable poolManager; // Uniswap V4 PoolManager
```

---

## Contract #4: MoltStreetFeeVault

Accumulates and distributes trading fees to token deployers / configured recipients.

### Design
- Authorized depositors (LP Locker, Hook) deposit fees tagged to a `feeOwner` address
- **Anyone can trigger `claim()` on behalf of a `feeOwner`** -- important for multisig wallets and contracts that can't initiate transactions
- Simple balance tracking with reentrancy protection

### Functions

```solidity
// Called by LP Locker or Hook to deposit fees
// Uses balance-delta pattern (checks actual balance change, not trusted amount param)
function storeFees(address feeOwner, address token, uint256 amount) external;

// Anyone can trigger -- sends accumulated fees to the feeOwner
function claim(address feeOwner, address token) external;

// View: how much can feeOwner claim of a given token
function availableFees(address feeOwner, address token) external view returns (uint256);
```

### Access Control
- Only allowlisted depositors (LP Locker, Hook) can call `storeFees()`
- Owner can add/remove depositors via `addDepositor(address)` / `removeDepositor(address)`
- `claim()` is **fully permissionless** (anyone can trigger it for any feeOwner)

### Storage
```solidity
mapping(address feeOwner => mapping(address token => uint256 balance)) public feesToClaim;
mapping(address depositor => bool isAllowed) public allowedDepositors;
```

### Events
```solidity
event FeesStored(address indexed depositor, address indexed feeOwner, address indexed token, uint256 amount);
event FeesClaimed(address indexed feeOwner, address indexed token, uint256 amount);
event DepositorAdded(address indexed depositor);
event DepositorRemoved(address indexed depositor);
```

### Errors
```solidity
error Unauthorized();
error NoFeesToClaim();
```

---

## Contract #5: MoltStreetLpLocker

Manages locked LP positions and handles fee collection from Uniswap V4 pools.

### Responsibilities
1. Receive token supply from the factory and mint LP positions on the Uniswap V4 pool
2. LP positions are **permanently locked** (no withdrawals, ever)
3. Collect LP fees when triggered by the Hook's `afterSwap`
4. Split user's portion of fees among configured recipients and deposit into the Fee Vault
5. Allow recipient admins to update their recipient addresses

### LP Position Config
- Up to **7 LP positions** per token with different tick ranges
- Each position gets a configurable share of the LP supply (`positionBps[]`, must sum to 10000)

### Fee Distribution
When fees arrive at the LP Locker:
1. Protocol fee (MoltStreet's cut) is already separated at the Hook level
2. The remaining fees are split among user-configured recipients per their `recipientBps[]`
3. Each recipient's share is deposited into the `MoltStreetFeeVault`

### Functions

```solidity
// Called by factory during deployment
function placeLiquidity(
    LiquidityConfig calldata liquidityConfig,
    FeeDistributionConfig calldata feeConfig,
    PoolConfig calldata poolConfig,
    PoolKey memory poolKey,
    uint256 tokenAmount,
    address token
) external;

// Called by hook after each swap to collect and distribute fees
function collectFees(address token) external;

// Recipient admin can update their recipient address
function updateRecipient(address token, uint256 index, address newRecipient) external;

// Recipient admin can transfer their admin role
function updateRecipientAdmin(address token, uint256 index, address newAdmin) external;
```

### Events
```solidity
event LiquidityPlaced(address indexed token, PoolId poolId, uint256 tokenAmount);
event FeesCollected(address indexed token, uint256 totalFees);
event RecipientUpdated(address indexed token, uint256 index, address oldRecipient, address newRecipient);
event RecipientAdminUpdated(address indexed token, uint256 index, address oldAdmin, address newAdmin);
```

---

## Contract #6: MoltStreetAirdrop

Extension contract for distributing tokens to a list of addresses. **No merkle trees** -- just direct transfers.

### How it Works

During token deployment, if `airdropConfig.enabled == true`:
1. The factory calls `MoltStreetAirdrop.receiveAndDistribute()`
2. The airdrop contract receives the total airdrop amount from the factory
3. It immediately loops through `recipients[]` and transfers `amounts[i]` to each `recipients[i]`
4. Tokens land directly in recipient wallets -- no claiming needed

### Why a Separate Contract?
- Keeps the factory clean and focused on orchestration
- Airdrop logic can be swapped/upgraded independently
- Gas limit: if the recipient list is very large, we need to handle it properly

### Gas Consideration
For very large recipient lists (hundreds of addresses), the transaction may hit block gas limits. The deployer bot should validate the list size off-chain before submitting. A practical limit of ~200 recipients per deployment is recommended.

### Functions

```solidity
// Called by factory during deployment
// Factory approves this contract, then this contract pulls tokens and distributes
function receiveAndDistribute(
    address token,
    uint256 totalAmount,
    address[] calldata recipients,
    uint256[] calldata amounts
) external;
```

### Validation (inside receiveAndDistribute)
- `msg.sender` must be the factory
- `recipients.length == amounts.length`
- `recipients.length > 0`
- `sum(amounts) == totalAmount`
- No zero addresses in recipients
- No zero amounts

### Storage
Minimal -- only needs to know the factory address. No persistent per-token storage needed since tokens are distributed immediately.

```solidity
address public immutable factory;
```

### Events
```solidity
event AirdropExecuted(address indexed token, uint256 totalAmount, uint256 recipientCount);
```

### Errors
```solidity
error OnlyFactory();
error ArrayLengthMismatch();
error EmptyRecipients();
error ZeroAddress();
error ZeroAmount();
error AmountMismatch();
```

---

## Events (Factory)

```solidity
// Deployment
event TokenDeployed(
    address indexed token,
    address indexed deployer,
    address indexed tokenOwner,
    string name,
    string symbol,
    string image,
    string metadata,
    string context,
    address pairedToken,
    address hook,
    PoolId poolId,
    int24 startingTick,
    uint16 lpBps,
    uint16 airdropBps,
    uint16 ownerBps,
    address[] feeRecipients,
    uint16[] feeRecipientBps
);

// Admin
event DeployerSet(address indexed deployer, bool enabled);
event PausedSet(bool paused);
event ProtocolFeeBpsSet(uint16 oldBps, uint16 newBps);
event FeeRecipientSet(address oldRecipient, address newRecipient);
event ProtocolFeesClaimed(address indexed token, address indexed recipient, uint256 amount);
event HookSet(address indexed hook, bool enabled);
event LockerSet(address indexed locker, address indexed hook, bool enabled);
```

### Factory Errors
```solidity
error Paused();
error NotWhitelistedDeployer();
error InvalidLpBps();                  // lpBps < 1500 or > 10000
error SupplyExceeded();                // lpBps + airdropBps > 10000
error InvalidAirdropConfig();          // array mismatch, zero address/amount, sum mismatch
error AirdropNotEnabled();             // airdropBps > 0 but enabled == false
error HookNotEnabled();
error LockerNotEnabled();
error ProtocolFeeTooHigh();            // > MAX_PROTOCOL_FEE_BPS (4000)
error FeeRecipientNotSet();
error InvalidFeeConfig();              // recipientBps don't sum to 10000, array mismatch
```

---

## Token Events (MoltStreetToken)
```solidity
event UpdateImage(string image);
event UpdateMetadata(string metadata);
event UpdateOwner(address indexed oldOwner, address indexed newOwner);
```

---

## Security Requirements

1. **ReentrancyGuard** on all external state-changing functions (factory, fee vault, locker)
2. **SafeERC20** for all token transfers
3. **Balance delta checks** in `FeeVault.storeFees()` -- check actual balance change, don't trust the `amount` parameter
4. **CREATE2 determinism** -- use salt properly for deterministic token addresses
5. **UUPS proxy security** -- only owner can call `_authorizeUpgrade()`, use OpenZeppelin's battle-tested implementation
6. **Interface checks** -- use `supportsInterface()` when enabling hooks/lockers
7. **Tick validation** -- ensure LP position ticks are valid (aligned with tickSpacing, within bounds)
8. **Protocol fee bounds** -- `setProtocolFeeBps()` must enforce `feeBps <= MAX_PROTOCOL_FEE_BPS`

---

## Deployment Order

```
Phase 1: Deploy Empty Proxy
  1. Deploy MoltStreetFactoryEmpty (minimal UUPS implementation, no logic)
  2. Deploy ERC1967Proxy(emptyImpl, "") -- this is the permanent factory address

Phase 2: Deploy Supporting Contracts
  3. Deploy MoltStreetFeeVault(owner)
  4. Deploy MoltStreetLpLocker(owner, feeVaultAddress)
  5. Deploy MoltStreetHook(poolManager, factoryProxyAddress)  // hook needs factory address for live fee reads
  6. Deploy MoltStreetAirdrop(factoryProxyAddress)

Phase 3: Deploy Real Implementation & Upgrade
  7. Deploy MoltStreetFactory (real implementation)
  8. Call proxy.upgradeToAndCall(realImpl, initialize(owner, feeRecipient, 2500))

Phase 4: Configure
  9.  factory.setHook(hookAddress, true)
  10. factory.setLocker(lockerAddress, hookAddress, true)
  11. factory.setDeployer(botAddress, true)
  12. factory.setPaused(false)                            // enable deployments
  13. feeVault.addDepositor(lockerAddress)
  14. feeVault.addDepositor(hookAddress)
```

Note: The hook and airdrop contracts reference the **proxy address** (permanent), not the implementation. This is why we deploy the proxy first with an empty implementation.

---

## Example Deployment Scenario

**Scenario**: A user wants to launch "MEME Token" paired with WETH.

**Configuration chosen by user (passed to deployer bot):**
- 20% supply to LP (single full-range position)
- 5% supply airdropped to 50 community members
- 75% sent directly to the token owner's wallet
- Trading fees split: 60% to creator, 40% to marketing wallet
  (These are shares of the USER's portion. MoltStreet's cut is read live.)
- MoltStreet protocol fee is currently set to 25%

**What happens:**
1. Deployer bot calls `factory.deployToken(config)`
2. `MoltStreetToken({name: "MEME", symbol: "MEME", ...})` deployed via CREATE2 → 1B tokens minted to factory
3. 200M tokens (20%) → LP Locker → minted as Uniswap V4 LP position
4. 50M tokens (5%) → Airdrop contract → immediately transferred to 50 addresses
5. 750M tokens (75%) → sent directly to token owner's wallet
6. Pool initialized with static fee (e.g., 1% buy fee, 1% sell fee)
7. Trading begins immediately
8. On each trade, the Hook collects fees:
   - Reads `factory.protocolFeeBps()` → currently 2500 (25%)
   - 25% of LP fees → MoltStreet treasury
   - 75% of LP fees → Fee Vault, split as:
     - 60% → creator wallet
     - 40% → marketing wallet
9. Owner changes protocolFeeBps to 1000 (10%) → next swap on ANY pool uses 10%
10. Recipients (or anyone on their behalf) call `feeVault.claim()` to withdraw

**Scenario 2: 100% to LP (community pool)**
- 100% supply to LP
- 0% airdrop, 0% to owner
- All fees go to a DAO treasury

---

## Scope Boundaries

### In scope for v1
- Token deployment with ERC20 + Permit + Votes + Burnable
- Whitelisted deployer access control
- Upgradeable factory (UUPS proxy with empty impl → real impl)
- Uniswap V4 pool creation with static fees
- Configurable protocol fee % (0-40%, updatable by owner, read live on every swap)
- Multiple fee recipients with configurable splits
- LP locking with up to 7 positions
- Direct-transfer airdrop (address array, no merkle, no vesting)
- Anyone-can-claim pattern for fees
- Pause/unpause deployments
- 100% to LP supported

### Deferred to v1.5
- MEV / sniper protection (2-block delay or auction)

### Deferred to v2
- Token lockup + vesting (vault)
- Airdrop with vesting
- Dynamic fee hook
- Additional extensions (dev buy, presale)
- Token verification feature

---

## File Structure

```
src/
├── MoltStreetFactory.sol            # Upgradeable factory (UUPS) -- real implementation
├── MoltStreetFactoryEmpty.sol       # Empty UUPS implementation (for initial proxy deploy)
├── MoltStreetToken.sol              # ERC20 token (Permit + Votes + Burnable)
├── MoltStreetHook.sol               # Uniswap V4 hook with static fees
├── MoltStreetFeeVault.sol           # Fee accumulation and claiming
├── MoltStreetLpLocker.sol           # LP position management and fee routing
├── MoltStreetAirdrop.sol            # Direct-transfer airdrop
├── interfaces/
│   ├── IMoltStreetFactory.sol
│   ├── IMoltStreetHook.sol
│   ├── IMoltStreetFeeVault.sol
│   ├── IMoltStreetLpLocker.sol
│   └── IMoltStreetAirdrop.sol
└── utils/
    ├── TokenDeployer.sol             # CREATE2 deployment helper
    └── OwnerAdmins.sol               # Owner + admin access control (for non-upgradeable contracts)

test/
├── MoltStreetToken.t.sol
├── MoltStreetFactory.t.sol
├── MoltStreetHook.t.sol
├── MoltStreetFeeVault.t.sol
├── MoltStreetLpLocker.t.sol
├── MoltStreetAirdrop.t.sol
├── integration/
│   ├── DeploymentFlow.t.sol
│   ├── FeeFlow.t.sol
│   └── UpgradeFlow.t.sol
└── helpers/
    ├── TestSetup.sol
    └── MockContracts.sol
```

---

## Detailed Test Suite

### test/MoltStreetToken.t.sol

```
MoltStreetTokenTest
├── Constructor
│   ├── test_constructor_setsInitialOwner
│   │     Deploy token, assert initialOwner() == params.owner
│   ├── test_constructor_setsOwner
│   │     Deploy token, assert owner() == params.owner
│   ├── test_constructor_setsName
│   │     Assert name() == params.name
│   ├── test_constructor_setsSymbol
│   │     Assert symbol() == params.symbol
│   ├── test_constructor_setsImage
│   │     Assert imageUrl() == params.image
│   ├── test_constructor_setsMetadata
│   │     Assert metadata() == params.metadata
│   ├── test_constructor_setsContext
│   │     Assert context() == params.context
│   ├── test_constructor_mintsFullSupplyToMsgSender
│   │     Assert balanceOf(msg.sender) == params.maxSupply
│   ├── test_constructor_totalSupplyEquals1B
│   │     Assert totalSupply() == 1_000_000_000e18
│   └── test_constructor_acceptsStructParam
│         Deploy with TokenParams struct, verify all fields
│
├── updateOwner
│   ├── test_updateOwner_success
│   │     Owner calls updateOwner(newOwner), assert owner() == newOwner
│   ├── test_updateOwner_emitsEvent
│   │     Expect UpdateOwner(oldOwner, newOwner) event
│   ├── test_updateOwner_revertsIfNotOwner
│   │     Non-owner calls → revert NotOwner()
│   ├── test_updateOwner_newOwnerCanUpdateAgain
│   │     Transfer to B, B transfers to C → owner() == C
│   └── test_updateOwner_initialOwnerUnchanged
│         After updateOwner, initialOwner() still returns original
│
├── updateImage
│   ├── test_updateImage_success
│   │     Owner calls updateImage("new.png"), assert imageUrl() == "new.png"
│   ├── test_updateImage_emitsEvent
│   │     Expect UpdateImage("new.png")
│   ├── test_updateImage_revertsIfNotOwner
│   │     Non-owner calls → revert NotOwner()
│   └── test_updateImage_emptyStringAllowed
│         Owner calls updateImage("") → succeeds
│
├── updateMetadata
│   ├── test_updateMetadata_success
│   ├── test_updateMetadata_emitsEvent
│   └── test_updateMetadata_revertsIfNotOwner
│
├── allData
│   └── test_allData_returnsAllFields
│         Call allData(), verify all 5 return values match
│
├── ERC20 Basics
│   ├── test_transfer_works
│   ├── test_approve_and_transferFrom_works
│   ├── test_transfer_revertsOnInsufficientBalance
│   └── test_decimals_returns18
│
├── ERC20Permit
│   ├── test_permit_validSignature
│   │     Sign EIP-2612 permit off-chain, call permit(), assert allowance set
│   ├── test_permit_revertsOnInvalidSignature
│   ├── test_permit_revertsOnExpiredDeadline
│   └── test_nonces_incrementsAfterPermit
│
├── ERC20Votes
│   ├── test_delegate_selfDelegation
│   │     User delegates to self, getVotes() == balance
│   ├── test_delegate_toOther
│   │     User A delegates to B, B.getVotes() == A.balance
│   ├── test_delegate_transferReducesVotes
│   │     After delegation, transfer reduces delegatee's votes
│   └── test_getPastVotes_returnsHistorical
│
├── ERC20Burnable
│   ├── test_burn_reducesTotalSupply
│   │     User burns 100 tokens, totalSupply decreases by 100
│   ├── test_burn_reducesUserBalance
│   ├── test_burnFrom_withAllowance
│   │     Approved spender burns on behalf of owner
│   └── test_burn_revertsOnInsufficientBalance
│
└── Edge Cases
    ├── test_transferToZeroAddress_reverts
    ├── test_supplyAfterBurn_correct
    └── test_contextIsImmutable
          Deploy, no function exists to change context
```

### test/MoltStreetFactory.t.sol

```
MoltStreetFactoryTest
├── Proxy & Upgrade
│   ├── test_proxy_initialImplementationIsEmpty
│   │     Deploy proxy with empty impl, verify it has no deployToken function
│   ├── test_proxy_upgradeToRealImplementation
│   │     Upgrade from empty → real impl, verify initialize() ran
│   ├── test_proxy_initializeSetsOwner
│   │     After upgrade+init, owner() == expected owner
│   ├── test_proxy_initializeSetsFeeRecipient
│   ├── test_proxy_initializeSetsProtocolFeeBps
│   ├── test_proxy_initializeStartsPaused
│   │     After init, paused == true
│   ├── test_proxy_cannotInitializeTwice
│   │     Call initialize again → revert (Initializable)
│   ├── test_proxy_onlyOwnerCanUpgrade
│   │     Non-owner calls upgradeTo → revert
│   ├── test_proxy_upgradePreservesState
│   │     Set state, upgrade to new impl, verify state preserved
│   └── test_proxy_addressStaysTheSame
│         Proxy address unchanged after upgrade
│
├── Deployer Management
│   ├── test_setDeployer_enablesDeployer
│   │     Owner sets deployer, assert whitelistedDeployers[deployer] == true
│   ├── test_setDeployer_disablesDeployer
│   │     Enable then disable deployer
│   ├── test_setDeployer_emitsEvent
│   ├── test_setDeployer_revertsIfNotOwner
│   └── test_setDeployer_multipleDeployers
│         Enable 3 different deployers, all can deploy
│
├── Pause / Unpause
│   ├── test_setPaused_pausesDeployments
│   │     Pause, try deployToken → revert Paused()
│   ├── test_setPaused_unpausesDeployments
│   │     Unpause, deployToken succeeds
│   ├── test_setPaused_emitsEvent
│   ├── test_setPaused_revertsIfNotOwner
│   └── test_setPaused_canToggleRepeatedly
│
├── Protocol Fee
│   ├── test_setProtocolFeeBps_updatesValue
│   │     Set to 3000, assert protocolFeeBps() == 3000
│   ├── test_setProtocolFeeBps_canSetToZero
│   │     Set to 0, assert protocolFeeBps() == 0
│   ├── test_setProtocolFeeBps_canSetToMax
│   │     Set to 4000 (40%), assert it works
│   ├── test_setProtocolFeeBps_revertsAboveMax
│   │     Set to 4001 → revert ProtocolFeeTooHigh()
│   ├── test_setProtocolFeeBps_emitsEvent
│   │     Expect ProtocolFeeBpsSet(oldBps, newBps)
│   └── test_setProtocolFeeBps_revertsIfNotOwner
│
├── Fee Recipient
│   ├── test_setMoltStreetFeeRecipient_updatesAddress
│   ├── test_setMoltStreetFeeRecipient_emitsEvent
│   ├── test_setMoltStreetFeeRecipient_revertsIfNotOwner
│   └── test_claimProtocolFees_sendsToRecipient
│         Accumulate fees, claim, verify recipient received
│
├── Module Allowlisting
│   ├── test_setHook_enablesHook
│   ├── test_setHook_disablesHook
│   ├── test_setHook_revertsIfNotOwner
│   ├── test_setLocker_enablesLockerForHook
│   ├── test_setLocker_disablesLockerForHook
│   └── test_setLocker_revertsIfNotOwner
│
├── deployToken -- Access Control
│   ├── test_deployToken_revertsWhenPaused
│   ├── test_deployToken_revertsIfNotWhitelisted
│   │     Random address calls → revert NotWhitelistedDeployer()
│   └── test_deployToken_succeedsForWhitelistedDeployer
│
├── deployToken -- Supply Split Validation
│   ├── test_deployToken_revertsIfLpBpsBelow1500
│   │     lpBps=1000 → revert InvalidLpBps()
│   ├── test_deployToken_revertsIfLpBpsAbove10000
│   │     lpBps=10001 → revert InvalidLpBps()
│   ├── test_deployToken_revertsIfLpPlusAirdropExceeds10000
│   │     lpBps=6000 + airdropBps=5000 → revert SupplyExceeded()
│   ├── test_deployToken_succeedsWithMinLpBps
│   │     lpBps=1500, airdrop=0, owner gets 85%
│   ├── test_deployToken_succeedsWith100PercentLp
│   │     lpBps=10000, airdrop=0, owner gets 0%
│   ├── test_deployToken_succeedsWithLpAndAirdrop
│   │     lpBps=2000, airdrop=1000, owner gets 70%
│   ├── test_deployToken_ownerGetsZeroWhenLpPlusAirdropIs100
│   │     lpBps=8000, airdrop=2000 → owner gets 0, no transfer to owner
│   └── test_deployToken_ownerGetsRemainderCorrectly
│         lpBps=1500 → owner gets exactly 85% of 1B = 850M tokens
│
├── deployToken -- Airdrop Validation
│   ├── test_deployToken_revertsIfAirdropEnabledButEmptyRecipients
│   ├── test_deployToken_revertsIfAirdropArrayLengthMismatch
│   │     recipients.length != amounts.length → revert
│   ├── test_deployToken_revertsIfAirdropAmountsSumMismatch
│   │     sum(amounts) != airdropBps * TOKEN_SUPPLY / BPS → revert
│   ├── test_deployToken_revertsIfAirdropHasZeroAddress
│   ├── test_deployToken_revertsIfAirdropHasZeroAmount
│   ├── test_deployToken_revertsIfAirdropBpsNonZeroButNotEnabled
│   │     enabled=false but airdropBps=500 → revert
│   └── test_deployToken_airdropDisabledByDefault
│         enabled=false, bps=0, empty arrays → succeeds, no airdrop
│
├── deployToken -- Token Creation
│   ├── test_deployToken_deploysTokenViaCreate2
│   │     Verify token address is deterministic based on salt
│   ├── test_deployToken_tokenHasCorrectName
│   ├── test_deployToken_tokenHasCorrectSymbol
│   ├── test_deployToken_tokenHasCorrectOwner
│   │     token.owner() == tokenConfig.tokenOwner
│   ├── test_deployToken_tokenTotalSupply1B
│   │     token.totalSupply() == 1_000_000_000e18
│   ├── test_deployToken_sameSaltSameAddress
│   │     Deploy with same salt and config → same address (but will revert because already deployed)
│   └── test_deployToken_differentSaltDifferentAddress
│
├── deployToken -- Pool Initialization
│   ├── test_deployToken_revertsIfHookNotEnabled
│   ├── test_deployToken_revertsIfLockerNotEnabled
│   ├── test_deployToken_initializesPoolOnUniV4
│   │     After deploy, pool exists on PoolManager with correct tick
│   └── test_deployToken_poolHasCorrectStaticFees
│
├── deployToken -- Supply Distribution
│   ├── test_deployToken_sendsLpTokensToLocker
│   │     Check locker received exactly lpBps% of 1B
│   ├── test_deployToken_sendsAirdropTokensToRecipients
│   │     Each recipient got their specified amount
│   ├── test_deployToken_sendsRemainingToOwner
│   │     tokenOwner received remainder
│   ├── test_deployToken_factoryHasZeroTokensAfter
│   │     factory.balanceOf(token) == 0 after deployment
│   └── test_deployToken_100PercentLpNoTokensToOwner
│         tokenOwner.balanceOf == 0 when lpBps=10000
│
├── deployToken -- Events
│   ├── test_deployToken_emitsTokenDeployedEvent
│   │     Verify all fields in the event
│   └── test_deployToken_eventContainsCorrectFeeRecipients
│
├── deployToken -- Stores DeploymentInfo
│   ├── test_deployToken_storesDeploymentInfo
│   │     deployments[token] returns correct token, hook, locker
│   └── test_deployToken_deploymentInfoQueryable
│         Call deployments(tokenAddr), verify all fields
│
└── Edge Cases
    ├── test_deployToken_reentrancyProtected
    │     Attempt reentrant call → revert
    ├── test_deployToken_multipleDeployments
    │     Deploy 3 different tokens, all succeed, all have unique addresses
    └── test_deployToken_hookNotEnabledAfterDisable
          Enable hook, deploy succeeds; disable hook, deploy reverts
```

### test/MoltStreetHook.t.sol

```
MoltStreetHookTest
├── Initialization
│   ├── test_initializePool_storesPoolInfo
│   │     After init, pools[poolId] has correct locker, token, pairedToken, fees
│   ├── test_initializePool_setsTokenIsToken0Correctly
│   │     When token address < pairedToken → tokenIsToken0 == true
│   ├── test_initializePool_decodesHookDataForFees
│   │     Verify buyFee and sellFee decoded from hookData
│   ├── test_initializePool_revertsIfNotFactory
│   │     Random address tries to initialize → revert
│   └── test_initializePool_setsInitializedFlag
│
├── afterSwap -- Fee Collection
│   ├── test_afterSwap_collectsLpFees
│   │     Swap, verify LP fees collected from pool
│   ├── test_afterSwap_appliesBuyFeeCorrectly
│   │     Buy swap uses buyFee, not sellFee
│   ├── test_afterSwap_appliesSellFeeCorrectly
│   │     Sell swap uses sellFee, not buyFee
│   ├── test_afterSwap_feesLagByOneSwap
│   │     First swap: no fees collected. Second swap: collects fees from first.
│   └── test_afterSwap_noFeesOnFirstSwap
│
├── afterSwap -- Protocol Fee (Live Read)
│   ├── test_afterSwap_readsProtocolFeeBpsFromFactory
│   │     Verify hook calls factory.protocolFeeBps()
│   ├── test_afterSwap_protocolFeeCalculatedCorrectly
│   │     25% of LP fees go to protocol at 2500 bps
│   ├── test_afterSwap_protocolFeeUpdatesLiveAcrossAllPools
│   │     Change factory.protocolFeeBps from 2500 → 1000,
│   │     next swap on existing pool uses 1000
│   ├── test_afterSwap_protocolFeeZero
│   │     Set protocolFeeBps to 0, all LP fees go to users
│   ├── test_afterSwap_protocolFeeMax40Percent
│   │     Set protocolFeeBps to 4000, verify 40% taken
│   ├── test_afterSwap_protocolFeeInPairedToken
│   │     Verify protocol fees are always in the paired token
│   └── test_afterSwap_userFeesRoutedToFeeVault
│         Remaining fees after protocol cut → fee vault
│
├── Pool Info Struct
│   ├── test_poolInfo_allFieldsStoredCorrectly
│   │     Read pools[poolId], verify every field in PoolInfo struct
│   └── test_poolInfo_multiplePoolsIndependent
│         Initialize 2 pools, verify they have independent PoolInfo
│
└── Edge Cases
    ├── test_swap_withZeroLiquidity
    ├── test_swap_revertsOnUninitializedPool
    └── test_multipleSwaps_feesAccumulateCorrectly
```

### test/MoltStreetFeeVault.t.sol

```
MoltStreetFeeVaultTest
├── Depositor Management
│   ├── test_addDepositor_success
│   │     Owner adds depositor, allowedDepositors[depositor] == true
│   ├── test_addDepositor_emitsEvent
│   ├── test_addDepositor_revertsIfNotOwner
│   ├── test_removeDepositor_success
│   ├── test_removeDepositor_emitsEvent
│   └── test_removeDepositor_revertsIfNotOwner
│
├── storeFees
│   ├── test_storeFees_incrementsBalance
│   │     Deposit 100 tokens, availableFees == 100
│   ├── test_storeFees_multipleDepositsAccumulate
│   │     Deposit 100, then 200 → availableFees == 300
│   ├── test_storeFees_revertsIfNotDepositor
│   │     Non-depositor calls → revert Unauthorized()
│   ├── test_storeFees_usesBalanceDelta
│   │     Even if amount param says 100, actual balance change is checked
│   ├── test_storeFees_emitsEvent
│   ├── test_storeFees_separateBalancesPerFeeOwner
│   │     Deposit for owner A and owner B, balances are independent
│   └── test_storeFees_separateBalancesPerToken
│         Deposit tokenX and tokenY for same owner, balances independent
│
├── claim
│   ├── test_claim_transfersFullBalance
│   │     Deposit 100, claim, feeOwner receives 100
│   ├── test_claim_resetsBalanceToZero
│   │     After claim, availableFees == 0
│   ├── test_claim_anyoneCanTrigger
│   │     Random address calls claim(feeOwner, token) → feeOwner receives
│   ├── test_claim_revertsIfNoFees
│   │     claim with 0 balance → revert NoFeesToClaim()
│   ├── test_claim_emitsEvent
│   ├── test_claim_multipleClaims
│   │     Deposit, claim, deposit again, claim again → both succeed
│   └── test_claim_reentrancyProtected
│
├── availableFees
│   ├── test_availableFees_returnsCorrectAmount
│   ├── test_availableFees_returnsZeroForUnknownOwner
│   └── test_availableFees_updatesAfterClaim
│
└── Edge Cases
    ├── test_storeFees_zeroAmount
    │     Depositing 0 → what happens? (should handle gracefully)
    └── test_claim_toContractAddress
          feeOwner is a contract → transfer still works
```

### test/MoltStreetLpLocker.t.sol

```
MoltStreetLpLockerTest
├── placeLiquidity
│   ├── test_placeLiquidity_mintsLpPositions
│   │     Verify LP positions minted on Uniswap V4 pool
│   ├── test_placeLiquidity_correctTokenAmounts
│   │     Amount received by locker == amount sent by factory
│   ├── test_placeLiquidity_multiplePositions
│   │     Place 3 positions with different tick ranges and BPS splits
│   ├── test_placeLiquidity_singlePosition
│   │     1 position, positionBps=[10000], full range
│   ├── test_placeLiquidity_positionBpsMustSumTo10000
│   │     [5000, 4000] → revert (sums to 9000)
│   ├── test_placeLiquidity_maxSevenPositions
│   │     8 positions → revert
│   ├── test_placeLiquidity_emitsEvent
│   └── test_placeLiquidity_storesFeeConfig
│         Fee recipients and BPS stored correctly for later distribution
│
├── collectFees
│   ├── test_collectFees_splitsAmongRecipients
│   │     2 recipients at 60/40 split, verify each gets correct share
│   ├── test_collectFees_depositsIntoFeeVault
│   │     After collection, feeVault.availableFees() reflects deposits
│   ├── test_collectFees_singleRecipient
│   │     1 recipient at 10000 BPS gets everything
│   └── test_collectFees_fiveRecipients
│         5 recipients with various splits, all get correct amounts
│
├── updateRecipient
│   ├── test_updateRecipient_success
│   │     Admin updates recipient, future fees go to new address
│   ├── test_updateRecipient_emitsEvent
│   ├── test_updateRecipient_revertsIfNotAdmin
│   │     Non-admin calls → revert
│   ├── test_updateRecipient_revertsIfInvalidIndex
│   │     Index out of bounds → revert
│   └── test_updateRecipient_newRecipientReceivesFees
│         Update recipient, next fee collection goes to new recipient
│
├── updateRecipientAdmin
│   ├── test_updateRecipientAdmin_success
│   ├── test_updateRecipientAdmin_emitsEvent
│   ├── test_updateRecipientAdmin_revertsIfNotCurrentAdmin
│   └── test_updateRecipientAdmin_newAdminCanUpdate
│         Transfer admin to B, B can now updateRecipient
│
└── LP Permanence
    └── test_lpPositions_cannotBeWithdrawn
          Verify there is no withdraw function, LP is locked forever
```

### test/MoltStreetAirdrop.t.sol

```
MoltStreetAirdropTest
├── receiveAndDistribute
│   ├── test_receiveAndDistribute_sendsToAllRecipients
│   │     10 recipients, each gets correct amount
│   ├── test_receiveAndDistribute_singleRecipient
│   │     1 recipient gets entire airdrop amount
│   ├── test_receiveAndDistribute_manyRecipients
│   │     100 recipients, all get correct amounts
│   ├── test_receiveAndDistribute_revertsIfNotFactory
│   │     Random address calls → revert OnlyFactory()
│   ├── test_receiveAndDistribute_revertsIfArrayLengthMismatch
│   │     recipients.length != amounts.length → revert
│   ├── test_receiveAndDistribute_revertsIfEmptyRecipients
│   │     Empty arrays → revert EmptyRecipients()
│   ├── test_receiveAndDistribute_revertsIfZeroAddress
│   │     address(0) in recipients → revert ZeroAddress()
│   ├── test_receiveAndDistribute_revertsIfZeroAmount
│   │     0 in amounts → revert ZeroAmount()
│   ├── test_receiveAndDistribute_revertsIfAmountsSumMismatch
│   │     sum(amounts) != totalAmount → revert AmountMismatch()
│   ├── test_receiveAndDistribute_emitsEvent
│   │     Expect AirdropExecuted(token, totalAmount, recipientCount)
│   └── test_receiveAndDistribute_tokensImmediatelyInWallets
│         After call, check each recipient's balanceOf == their amount
│
└── Edge Cases
    ├── test_receiveAndDistribute_duplicateRecipients
    │     Same address appears twice → both transfers succeed, they get sum
    ├── test_receiveAndDistribute_largeNumberOfRecipients
    │     200 recipients → test gas usage
    └── test_receiveAndDistribute_entireSupplyAirdropped
          lpBps=1500, airdropBps=8500 → 85% airdropped, owner gets 0
```

### test/integration/DeploymentFlow.t.sol

```
DeploymentFlowIntegrationTest
├── Full Deployment -- Standard Config
│   ├── test_e2e_standardDeployment
│   │     15% LP, 5% airdrop to 10 addresses, 80% to owner
│   │     Verify: token deployed, pool created, LP minted,
│   │     airdrop distributed, owner has tokens, factory has 0
│   └── test_e2e_standardDeployment_poolIsTradeable
│         After deployment, execute a swap on the pool → succeeds
│
├── Full Deployment -- 100% LP
│   ├── test_e2e_fullLpDeployment
│   │     100% to LP, 0% airdrop, 0% to owner
│   │     Verify: all tokens in LP, owner has 0, airdrop has 0
│   └── test_e2e_fullLpDeployment_tradeableAndCollectsFees
│
├── Full Deployment -- LP + Airdrop, No Owner Allocation
│   └── test_e2e_lpAndAirdropNoOwner
│         50% LP, 50% airdrop to 20 addresses, owner gets 0
│
├── Full Deployment -- Minimum LP
│   └── test_e2e_minimumLp
│         15% LP, 0% airdrop, 85% to owner
│
├── Multiple Tokens
│   └── test_e2e_deployMultipleTokens
│         Deploy 3 tokens in sequence, all with different configs,
│         verify all are independent and functional
│
└── Different Paired Tokens
    └── test_e2e_nonWethPairedToken
          Deploy with USDC as paired token instead of WETH
```

### test/integration/FeeFlow.t.sol

```
FeeFlowIntegrationTest
├── End-to-End Fee Collection
│   ├── test_e2e_feeFlow_swapCollectsAndDistributes
│   │     Deploy token, execute swap, verify:
│   │     - Hook collected LP fees
│   │     - Protocol fee sent to MoltStreet
│   │     - User fees deposited in FeeVault
│   │     - Recipients can claim from FeeVault
│   │
│   ├── test_e2e_feeFlow_multipleSwapsAccumulate
│   │     Execute 10 swaps, verify fees accumulate correctly
│   │
│   ├── test_e2e_feeFlow_multipleRecipientsGetCorrectShares
│   │     3 recipients at 50/30/20, verify after swaps
│   │
│   └── test_e2e_feeFlow_claimPartialThenAccumulateMore
│         Claim after 5 swaps, do 5 more swaps, claim again
│
├── Protocol Fee Live Updates
│   ├── test_e2e_protocolFeeChange_affectsNextSwap
│   │     Deploy at 25%, swap, change to 10%, swap again
│   │     Verify second swap uses 10%
│   │
│   ├── test_e2e_protocolFeeSetToZero
│   │     Set to 0%, swap, verify 0 protocol fees, 100% to users
│   │
│   └── test_e2e_protocolFeeSetToMax
│         Set to 40%, swap, verify 40% to protocol, 60% to users
│
├── Cross-Pool Fee Updates
│   └── test_e2e_protocolFeeChange_affectsAllPools
│         Deploy 2 tokens (2 pools), change protocolFeeBps,
│         swap on both → both use new fee
│
└── Claim Flows
    ├── test_e2e_anyoneCanClaimForFeeOwner
    │     Random address calls claim(feeOwner, token) → feeOwner receives
    └── test_e2e_claimProtocolFees
          Owner calls claimProtocolFees → moltstreetFeeRecipient receives
```

### test/integration/UpgradeFlow.t.sol

```
UpgradeFlowIntegrationTest
├── Empty → Real Upgrade
│   ├── test_upgrade_emptyToRealImplementation
│   │     Deploy proxy with empty impl, upgrade to real, initialize
│   │     Verify factory is functional after upgrade
│   │
│   ├── test_upgrade_proxyAddressUnchanged
│   │     Verify proxy address same before and after upgrade
│   │
│   └── test_upgrade_hookReferencesCorrectProxyAddress
│         Hook was deployed with proxy address, still works after upgrade
│
├── Real → Real V2 Upgrade
│   ├── test_upgrade_preservesDeployerWhitelist
│   │     Set deployers, upgrade, verify deployers still enabled
│   │
│   ├── test_upgrade_preservesDeploymentInfo
│   │     Deploy token, upgrade factory, verify deployments[token] still correct
│   │
│   ├── test_upgrade_preservesProtocolFeeBps
│   │     Set fee, upgrade, verify fee unchanged
│   │
│   └── test_upgrade_preservesPausedState
│
└── Security
    ├── test_upgrade_revertsIfNotOwner
    │     Non-owner calls upgradeToAndCall → revert
    └── test_upgrade_cannotReinitialize
          After upgrade, calling initialize again → revert
```
```

---

## Summary of Changes from Previous Version

| Change | Before | After |
|--------|--------|-------|
| SuperChain | IERC7802 + crosschainMint/Burn | Removed entirely |
| Airdrop | Merkle tree with proofs | Direct transfer to address arrays |
| Total supply | 100 billion | 1 billion |
| Token naming | `_originalAdmin` / `_admin` | `_initialOwner` / `_owner` |
| Token constructor | Positional params | Struct param (`TokenParams`) |
| originatingChainId | Used for cross-chain supply | Removed entirely |
| Factory | Immutable | Upgradeable (UUPS proxy, deployed with empty impl first) |
| Min LP | 15% minimum | 15% minimum, up to 100% allowed |
| Protocol fee storage | Per-pool or fixed | Single global variable, read LIVE on every swap |
| Protocol fee range | Fixed 25% | 0% to 40%, updatable by owner |
| Hook pool storage | Multiple separate mappings | Single `mapping(PoolId => PoolInfo)` struct |
| Token verification | `verify()` function | Removed (deferred) |
| Airdrop vesting | Deferred | Removed from spec entirely for v1 |
| Test suite | Checklist only | Full detailed test tree with descriptions |

# MoltStreet — Ship Plan

## What We're Building

A Twitter bot that lets anyone deploy tokens on Base (Uniswap V4) by tweeting. Bankr competitor. Own contracts, own infra, MoltX ecosystem.

## Stack

- **Contracts:** Thrilok's spec (`MOLTSTREET_SPEC.md`) — 6 Solidity contracts on Foundry
- **Wallets:** Mogra custodial wallets (no Privy, no MetaMask)
- **Bot:** Twitter/X listener → parses tweet → deploys token → replies with link
- **Backend:** Node.js service, PostgreSQL, Redis pub/sub
- **Indexer:** On-chain event indexer for token pages
- **Frontend:** Token page (chart, price, LP info, fees)

## What's In / Out for V1

**IN:**
- Tweet-to-deploy (mention @moltstreet → token launches on Base)
- Mogra custodial wallet per user (auto-created on first interaction)
- Token deployment via MoltStreetFactory contracts
- LP auto-locked, fee distribution to creator
- Token page with chart (DexScreener/GeckoTerminal embed or custom)
- Fee dashboard for creators (see earnings, claim)
- Agent API (REST) for programmatic deploys
- Anti-sybil: IP + rate limiting (1 deploy/day default)

**OUT (later):**
- NLP parser (not needed — structured commands for now)
- MEV/sniper protection (v1.5)
- Trading engine (swaps, limit orders)
- Multi-chain (Base only for v1)
- Vesting/lockup
- Dynamic fees

## Architecture

```
Tweet "@moltstreet deploy $MOON"
        │
        ▼
┌──────────────────┐
│  Twitter Listener │ ← X API v2 filtered stream
│  (Node.js)        │ ← monitors @moltstreet mentions
└────────┬─────────┘
         │ parse command
         ▼
┌──────────────────┐
│  Token Deployer   │ ← validates ticker, checks rate limits
│  (Node.js)        │ ← calls MoltStreetFactory.deployToken()
│                    │ ← uses Mogra custodial wallet to sign tx
└────────┬─────────┘
         │ tx confirmed
         ▼
┌──────────────────┐
│  Reply Bot        │ ← tweets back: token address, pool link,
│                    │   DexScreener chart URL
└──────────────────┘
         │
         ▼
┌──────────────────┐
│  Indexer           │ ← watches on-chain events
│  (Ponder/custom)   │ ← feeds token page + fee dashboard
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Token Page        │ ← chart, price, holders, LP info
│  (Next.js)         │ ← fee claims, creator dashboard
└──────────────────┘
```

## Contracts (Thrilok building)

| Contract | Status |
|----------|--------|
| MoltStreetToken | Spec done |
| MoltStreetFactory | Spec done |
| MoltStreetHook | Spec done |
| MoltStreetFeeVault | Spec done |
| MoltStreetLpLocker | Spec done |
| MoltStreetAirdrop | Spec done |

Full spec: `MOLTSTREET_SPEC.md` (1,431 lines, covers all 6 contracts + 150 test cases)

## Services We Build

**1. Twitter Listener**
- X API v2 filtered stream on @moltstreet mentions
- Parse command format: `@moltstreet deploy $TICKER [name] [options]`
- Options: `lp:30%`, `airdrop:5% @user1 @user2`, `fees:60% creator 40% treasury`
- Rate limit: 1 deploy per user per day
- Reply with confirmation or error

**2. Token Deployer**
- Receives parsed deploy commands from Twitter listener (via Redis)
- Validates: ticker not taken, supply config valid, user wallet exists
- If user has no wallet → create Mogra custodial wallet
- Build `DeploymentConfig` struct → call `factory.deployToken()`
- Sign tx with deployer bot wallet (whitelisted on factory)
- Return tx hash + token address

**3. Indexer**
- Watch `TokenDeployed` events from factory
- Index: token address, creator, pool, LP positions, fee config
- Track: volume, price, holder count, fee accruals
- Feed data to token page + API

**4. Token Page / Frontend**
- `moltstreet.xyz/{ticker}` — public token page
- Chart (DexScreener embed or custom via indexed data)
- Token info: supply, LP locked %, airdrop recipients, creator
- Fee dashboard: creator earnings, claim button
- Leaderboard: top tokens by volume

**5. Agent API**
- `POST /api/deploy` — deploy token programmatically
- `GET /api/token/{address}` — token info
- `GET /api/fees/{address}` — fee earnings
- Auth: API key per agent/user
- Same deployer backend as Twitter bot

## Fee Structure

**Swap fees (per token, set at deploy):** Default 1% buy, 1% sell (static)

**Protocol fee (MoltStreet's cut):** 25% of LP fees (configurable 0-40%, live update across all pools)

**Remaining 75% split (creator configurable):**
- Default: 40% creator, 30% MOLTX stakers, 20% treasury, 10% ops
- Creator can customize recipients at deploy time

## Wallet Flow

1. User tweets deploy command
2. Bot checks if user has Mogra wallet → if not, creates one
3. Token deploys, creator is set to user's Mogra wallet
4. Fees accrue to FeeVault tagged to creator's wallet
5. Creator claims via token page or API

## Deploy Order

1. Contracts (Thrilok) → deploy to Base testnet → audit → mainnet
2. Twitter listener + deployer bot → connect to testnet contracts
3. Indexer → start indexing testnet events
4. Token page → basic UI showing deployed tokens
5. Mainnet flip → go live

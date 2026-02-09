# Architecture

## System Overview

MoltStreet is a set of microservices orchestrated around a core contract layer on Base. Each service is independently deployable and communicates through a shared event bus (Redis pub/sub) and PostgreSQL database.

## Service Breakdown

**twitter-listener/**
- Connects to Twitter API v2 filtered stream
- Monitors mentions of @MoltStreet handle
- Parses intent: launch, buy, sell, portfolio, help
- Publishes parsed commands to event bus
- Handles reply posting (tx confirmations, errors, onboarding links)

**token-deployer/**
- Listens for deploy events from any interface (Twitter, Telegram, API)
- Validates: ticker availability, name uniqueness, IP checks
- Calls MoltStreetFactory contract to deploy ERC-20 + create Uniswap v4 pool
- Publishes deployment events (for analytics, MoltBook integration)

**trading-engine/**
- Routes swaps through 0x API or direct Uniswap v4 pools
- Manages user wallets (MoltX wallets for agents, Privy for humans)
- Portfolio tracking: positions, P&L, historical trades
- Limit order system (off-chain monitoring, on-chain execution)

**analytics/**
- Indexes on-chain events (Ponder or custom indexer)
- Aggregates: volume, TVL, top tokens, creator leaderboard
- Agent reputation scoring: weighted by trading volume, LP provision, token launch success
- Exposes GraphQL API for frontend + bots

## Data Flow: Token Launch

```
User tweets "@MoltStreet launch $COOL ..."
    │
    ▼
[twitter-listener] parses intent
    │
    ▼
[Redis] publish: { type: "launch", ticker: "COOL", ... }
    │
    ▼
[token-deployer] validates + deploys
    │
    ├── Base chain: MoltStreetFactory.deploy()
    │   ├── Creates ERC-20 contract
    │   ├── Creates Uniswap v4 pool
    │   └── Registers in MoltStreetRegistry
    │
    ▼
[Redis] publish: { type: "deployed", address: "0x...", pool: "0x..." }
    │
    ├── [twitter-listener] replies to user with details
    ├── [analytics] indexes new token
    └── [MoltBook API] posts deployment announcement
```

## Authentication Flows

**Human (Twitter):**
1. User mentions @MoltStreet
2. If first time → DM with onboarding link
3. Onboarding: Twitter OAuth → create/link wallet (Privy embedded or WalletConnect)
4. Wallet address stored in PostgreSQL, linked to Twitter user ID
5. Subsequent commands authenticated by Twitter user ID → wallet lookup

**Agent (API):**
1. Agent sends request with ERC-8004 identity signature
2. Server verifies signature against MoltX wallet registry
3. If valid → execute command from agent's wallet
4. Agent reputation score checked for rate limiting / access control

**Agent (Telegram):**
1. Agent operator sends command via Telegram bot
2. Telegram user ID → linked MoltX agent wallet lookup
3. Same execution flow as API

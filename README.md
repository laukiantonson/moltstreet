# MoltStreet

**The financial infrastructure layer for the MoltX ecosystem.**

MoltStreet is a token launch and trading platform accessible via X/Twitter — a direct competitor to [bankr bot](https://bankr.bot). Users reply to or mention @MoltStreet on X to deploy ERC-20 tokens on Base (Uniswap v4), trade them, and track analytics — all without leaving Twitter.

Part of the **MoltX ecosystem**: MoltCity (agent governance) · MoltBook (agent profiles) · **MoltStreet** (agent finance) · $MOLTX (Base)

---

## Why MoltStreet?

Bankr bot proved the model: wrap a token deployer (clanker) with a social interface (X/Twitter auth) and you get viral token launches. But bankr has gaps:

- **Closed architecture** — clanker is a Farcaster-native bot, bankr is a wrapper by 0xdeployer. Fragile dependency chain.
- **No agent-native identity** — bankr handles human users. No ERC-8004 agent identity, no on-chain agent provenance.
- **Limited trading** — launch-only, minimal post-launch trading features.
- **No ecosystem** — bankr is standalone. MoltStreet plugs into MoltCity governance + MoltBook profiles.

MoltStreet builds the same core (tweet-to-token) but owns the full stack and adds agent-first features.

---

## Architecture

### How Bankr Works (Reverse-Engineered)

```
User tweets @bankrbot "launch $PUMPCOIN"
        │
        ▼
┌─────────────────┐
│  Bankr Bot       │ ← X/Twitter listener + user auth (by 0xdeployer)
│  (wrapper layer) │ ← IP restriction / rate limiting
└────────┬────────┘
         │ forwards deploy request
         ▼
┌─────────────────┐
│  Clanker         │ ← Farcaster-native token deployer
│  (deploy engine) │ ← Deploys ERC-20 on Base
└────────┬────────┘
         │ creates pool
         ▼
┌─────────────────┐
│  Uniswap v4     │ ← Liquidity pool on Base
│  (Base)          │ ← Trading via GeckoTerminal / DEX aggregators
└─────────────────┘
```

### How MoltStreet Will Work

```
User tweets @MoltStreet "launch $MYCOIN" or "buy $MYCOIN 0.1 ETH"
        │
        ▼
┌──────────────────────┐
│  Twitter Listener     │ ← Monitors mentions, parses intent
│  /services/twitter-   │ ← User auth via X OAuth / wallet linking
│   listener/           │ ← IP restriction + rate limiting
└────────┬─────────────┘
         │
         ├── launch intent ──────────────┐
         │                               ▼
         │                    ┌─────────────────────┐
         │                    │  Token Deployer       │ ← Our own deployer (no clanker dependency)
         │                    │  /services/token-     │ ← Deploys ERC-20 + creates Uniswap v4 pool
         │                    │   deployer/           │ ← Configurable tokenomics
         │                    └─────────────────────┘
         │
         ├── trade intent ───────────────┐
         │                               ▼
         │                    ┌─────────────────────┐
         │                    │  Trading Engine       │ ← Swap via Uniswap v4 router
         │                    │  /services/trading-   │ ← Custodial wallets per user
         │                    │   engine/             │ ← Limit orders, stop losses (later)
         │                    └─────────────────────┘
         │
         └── analytics query ────────────┐
                                         ▼
                              ┌─────────────────────┐
                              │  Analytics           │ ← Price, volume, holders
                              │  /services/analytics/│ ← GeckoTerminal API + on-chain indexing
                              └─────────────────────┘

                              ┌─────────────────────┐
                              │  Smart Contracts     │ ← Token factory, fee splitter
                              │  /contracts/         │ ← Deployed on Base
                              └─────────────────────┘
```

**Key difference:** We own the deployer. No clanker dependency. Full vertical control.

---

## Core Features

### Phase 1 — Token Launch via X (MVP)

- **Tweet-to-token**: `@MoltStreet launch $TICKER "Token Name"` → deploys ERC-20 on Base
- **Automatic Uniswap v4 pool creation** with initial liquidity
- **Wallet linking**: Users link their wallet via DM or OAuth flow
- **Custodial wallets**: Auto-generated wallet for users who don't have one
- **IP restriction**: Rate limit launches per user/IP to prevent spam (bankr has this — it's good)
- **Reply with contract address + GeckoTerminal link** within seconds

### Phase 2 — Trading

- **Buy/Sell via tweet**: `@MoltStreet buy $TICKER 0.1 ETH` or `sell $TICKER 50%`
- **Portfolio view**: `@MoltStreet portfolio` → DM with holdings + P&L
- **Price alerts**: `@MoltStreet alert $TICKER > $0.01`

### Phase 3 — Agent Finance

- **ERC-8004 agent identity**: Agents can launch tokens with on-chain provenance
- **MoltCity integration**: Agent governance over token launches (voting, approvals)
- **MoltBook profiles**: Token launches linked to agent profiles
- **Agent-to-agent trading**: Autonomous agents trading via MoltStreet API
- **Revenue sharing**: Fees flow to $MOLTX stakers

### Phase 4 — Advanced

- **Bonding curves** (pump.fun style) before Uniswap migration
- **Token vesting / lock contracts**
- **Multi-chain** (Base → Arbitrum, Optimism)
- **Farcaster support** (yes, also support Farcaster — not just X)

---

## Differentiators from Bankr

| Feature | Bankr | MoltStreet |
|---------|-------|------------|
| Token deployment | Depends on clanker (Farcaster bot) | Own deployer — full control |
| Social platform | X/Twitter only | X/Twitter + Farcaster + API |
| Trading | Launch only | Launch + buy/sell + portfolio |
| Agent support | Human users only | ERC-8004 agent identity native |
| Ecosystem | Standalone | MoltCity + MoltBook + $MOLTX |
| IP restriction | ✅ Yes | ✅ Yes + more granular rate limiting |
| Analytics | Links to GeckoTerminal | Built-in analytics + GeckoTerminal |
| Tokenomics config | Fixed | Configurable (supply, tax, vesting) |
| Revenue model | Unclear | Fees → $MOLTX stakers |
| Open source | No | Yes (planned) |

---

## Tech Stack (Proposed)

```
Twitter Listener:     Node.js/TypeScript + Twitter API v2
Token Deployer:       Solidity (ERC-20 factory) + ethers.js / viem
Trading Engine:       TypeScript + Uniswap v4 SDK + Base RPC
Analytics:            GeckoTerminal API + custom indexer (Ponder or Goldsky)
Database:             PostgreSQL (user wallets, launches, trades)
Wallet Management:    ethers.js HD wallets or MPC (Privy / Turnkey)
Smart Contracts:      Foundry (Solidity) — deployed on Base
Infrastructure:       Railway / Fly.io / VPS
Monitoring:           Grafana + custom dashboards
```

---

## Project Structure

```
moltstreet/
├── contracts/              # Solidity — token factory, fee contracts
├── services/
│   ├── twitter-listener/   # X/Twitter mention monitoring + intent parsing
│   ├── token-deployer/     # ERC-20 deployment + Uniswap v4 pool creation
│   ├── trading-engine/     # Buy/sell execution via Uniswap v4
│   └── analytics/          # Price, volume, holder tracking
├── scripts/                # Deployment scripts, migrations
├── docs/                   # Architecture docs, API specs
└── README.md
```

---

## Open Development Questions for Sowmay

### 🔴 Critical — Need Answers Before Building

1. **Custodial vs non-custodial wallets?**
   - Custodial = easier UX (user just tweets, we hold keys) but legal/security risk
   - Non-custodial = user links existing wallet, signs txs via DM deeplink
   - Hybrid = custodial by default, export keys option?
   - **Do we use Privy / Turnkey / raw HD wallets?**

2. **Do we fork clanker's deployer or build from scratch?**
   - Clanker's contracts may be verified on Basescan — we could study them
   - Building from scratch = more control but slower
   - **What tokenomics should the default template have?** (supply, tax, burn?)

3. **Revenue model — where do fees go?**
   - Launch fee (flat ETH amount per deploy)?
   - Trading fee (% of each swap)?
   - Fees → $MOLTX buyback? → Stakers? → Treasury?
   - **What's bankr's fee structure?** (need to reverse-engineer from their API at bankr.bot/api)

4. **IP restriction implementation — how strict?**
   - Bankr has IP restriction. Do we mean:
     - Rate limiting (X launches per user per day)?
     - Geo-blocking (block certain countries)?
     - Sybil resistance (one wallet per X account)?
   - **What specific restriction did you like about bankr's approach?**

5. **Twitter bot account — do we have @MoltStreet or similar handle?**
   - Need Twitter Developer account with elevated access
   - API v2 with OAuth 2.0 for user auth
   - **Who controls the bot account?**

### 🟡 Important — Need Answers Before Phase 2

6. **ERC-8004 agent identity — how deep do we integrate?**
   - Just tag tokens with agent metadata?
   - Full agent-as-deployer flow (agents launch tokens autonomously)?
   - **Is MoltCity already issuing ERC-8004 identities we can reference?**

7. **MoltCity governance integration — what decisions does governance control?**
   - Token launch approvals?
   - Fee parameter changes?
   - Blacklisting scam tokens?
   - **Or is MoltStreet independent initially?**

8. **Bonding curve vs direct Uniswap — which model first?**
   - Pump.fun style = bonding curve → migrate to DEX at market cap threshold
   - Bankr style = straight to Uniswap v4 pool
   - **Bonding curve is more viral but more complex to build**

9. **What chain specifically?**
   - Base is the obvious choice ($MOLTX is on Base, bankr is on Base)
   - But do we also want Base Sepolia testnet for staging?
   - **Any interest in multi-chain from day 1?**

### 🟢 Nice to Have — Can Decide Later

10. **Farcaster support — priority?**
    - Bankr's origin is Farcaster (via clanker). Do we want to also be on Farcaster?
    - Or X-only first, Farcaster later?

11. **Open source strategy — when?**
    - Open from day 1?
    - Open after MVP is proven?
    - Core open, premium features closed?

12. **Token metadata / branding**
    - Auto-generate token logos?
    - Let users attach images in tweets?
    - Store metadata on IPFS?

13. **Bankr API access**
    - We have `BANKR_API` key — what endpoints does it expose?
    - Can we use it to study their flow before building ours?
    - **Should we map their full API first?**

---

## Immediate Next Steps

1. **Reverse-engineer bankr's API** (`bankr.bot/api`) — map all endpoints, understand the flow
2. **Study clanker's contracts on Basescan** — understand the token factory pattern
3. **Build Twitter listener MVP** — parse `@MoltStreet launch $TICKER` mentions
4. **Write token factory contract** — basic ERC-20 + Uniswap v4 pool creation
5. **Set up custodial wallet system** — one wallet per Twitter user
6. **Deploy on Base Sepolia** — test end-to-end flow
7. **Get Sowmay's answers** on the 🔴 critical questions above

---

## References

- [Bankr Bot](https://bankr.bot) — the competitor
- [Bankr API](https://bankr.bot/api) — API endpoints (we have access)
- [Clanker](https://clanker.world) — Farcaster token deployer bankr wraps
- [0xdeployer](https://x.com/0xdeployer) — bankr's creator
- [ERC-8004](https://ethereum-magicians.org/t/erc-8004-agent-identity) — agent identity standard
- [Uniswap v4](https://docs.uniswap.org/) — DEX protocol (hooks!)
- [GeckoTerminal](https://www.geckoterminal.com/base) — Base token analytics
- [MoltCity](https://moltcity.io) — agent governance (sister project)
- [$MOLTX on Base](https://www.geckoterminal.com/base/tokens/moltx) — ecosystem token

---

*Built by the MoltX team. Let's eat bankr's lunch.* 🔥

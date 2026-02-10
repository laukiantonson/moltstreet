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

MoltStreet builds the same core (tweet-to-token) using clanker directly — same deploy engine as bankr — but wraps it with a superior social layer, MoltX ecosystem integration, and a roadmap toward agent-first features (ERC-8004).

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
│   listener/           │ ← IP restriction + anti-sybil measures
└────────┬─────────────┘
         │
         ├── launch intent ──────────────┐
         │                               ▼
         │                    ┌─────────────────────┐
         │                    │  Clanker Integration  │ ← Uses clanker directly (same as bankr)
         │                    │  /services/clanker-   │ ← ERC-20 deploy + Uniswap v4 pool
         │                    │   bridge/             │ ← Clanker handles LP + indexing
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
                              │  /services/analytics/│ ← Clanker indexing + GeckoTerminal API
                              └─────────────────────┘

                              ┌─────────────────────┐
                              │  Fee Layer           │ ← Matches bankr's fee structure
                              │  /services/fees/     │ ← Fees → $MOLTX stakers
                              └─────────────────────┘
```

**Key difference:** We use clanker directly (same deploy engine as bankr). Our differentiation is the social layer, MoltX ecosystem integration, and future agent-first features — not reinventing the deployer.

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
| Token deployment | Clanker (Farcaster bot) | Also clanker — same engine, better wrapper |
| Social platform | X/Twitter only | X/Twitter + Farcaster + API |
| Trading | Launch only | Launch + buy/sell + portfolio |
| Agent support | Human users only | Human-first MVP → ERC-8004 agent identity (Phase 3) |
| Ecosystem | Standalone | MoltCity + MoltBook + $MOLTX |
| IP/Anti-sybil | ✅ Yes | ✅ Yes + IP protection + anti-sybil |
| Analytics/Indexing | Clanker indexing | Clanker indexing + GeckoTerminal |
| Fee structure | Their fee model | Match bankr fees initially |
| Revenue model | Unclear | Fees → $MOLTX stakers |
| Open source | No | Yes (planned) |

---

## Strategic Decisions (Resolved)

Sowmay's answers to the 9 core development questions (from Donald Pump group):

| # | Question | Decision | Implication |
|---|----------|----------|-------------|
| 1 | Fork clanker or build from scratch? | **Use clanker directly** | No custom deployer — integrate clanker's existing infra as bankr does |
| 2 | Own Uniswap hook or clanker's? | **Use clanker's** | Less custom smart contract work, faster to market |
| 3 | LP model? | **Uniswap v4** (via clanker) | Clanker already handles pool creation on Uniswap v4 |
| 4 | Agent-first or human-first? | **Human first** | MVP targets human users via X/Twitter; agent features (ERC-8004) come in Phase 3 |
| 5 | Compete with bankr or integrate? | **Compete** | MoltStreet is a direct competitor, not a bankr integration |
| 6 | Fee structure? | **Follow bankr's fee structure** | Reverse-engineer bankr's fees and match them initially |
| 7 | Indexing? | **Clanker provides that** | No custom indexer needed — use clanker's indexing layer |
| 8 | ERC-8004? | **Yes, research** | Research ERC-8004 for agent identity — not MVP-blocking but on roadmap |
| 9 | Anti-sybil/IP protection? | **Yes, IP protection** | Implement IP-based rate limiting + anti-sybil measures |

### What This Means for Architecture

- **We are NOT building a custom token deployer.** We use clanker directly (same as bankr). Our differentiation is the social layer, ecosystem integration, and agent features — not the deploy engine.
- **No custom Uniswap hooks.** Clanker handles pool creation and LP management.
- **No custom indexer.** Clanker's indexing covers token discovery and analytics.
- **Human-first MVP.** ERC-8004 agent identity is Phase 3, not Phase 1.
- **Competitive positioning.** We compete with bankr head-on, matching their fees while adding MoltX ecosystem value.

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
├── services/
│   ├── twitter-listener/   # X/Twitter mention monitoring + intent parsing
│   ├── clanker-bridge/     # Clanker integration — token deploy + pool creation
│   ├── trading-engine/     # Buy/sell execution via Uniswap v4
│   ├── fees/               # Fee layer — matches bankr's structure
│   └── analytics/          # Clanker indexing + GeckoTerminal
├── contracts/              # Solidity — fee splitter, future agent contracts
├── scripts/                # Deployment scripts, migrations
├── docs/                   # Architecture docs, API specs
└── README.md
```

---

## Open Development Questions

### ✅ Resolved (Sowmay's Decisions)

1. ~~**Fork clanker or build from scratch?**~~ → **Use clanker directly.** No custom deployer.
2. ~~**Own Uniswap hook or clanker's?**~~ → **Use clanker's.** No custom hooks.
3. ~~**LP model?**~~ → **Uniswap v4** via clanker.
4. ~~**Agent-first or human-first?**~~ → **Human first.** Agent features in Phase 3.
5. ~~**Compete with bankr or integrate?**~~ → **Compete.** Direct competitor.
6. ~~**Fee structure?**~~ → **Follow bankr's fee structure.** Need to reverse-engineer from bankr.bot/api.
7. ~~**Indexing?**~~ → **Clanker provides that.** No custom indexer.
8. ~~**ERC-8004?**~~ → **Yes, research.** Not MVP-blocking but on roadmap.
9. ~~**Anti-sybil/IP protection?**~~ → **Yes, IP protection.** Implement rate limiting + anti-sybil.

### 🔴 Still Open — Need Answers Before Building

1. **Custodial vs non-custodial wallets?**
   - Custodial = easier UX (user just tweets, we hold keys) but legal/security risk
   - Non-custodial = user links existing wallet, signs txs via DM deeplink
   - **Do we use Privy / Turnkey / raw HD wallets?**

2. **Twitter bot account — do we have @MoltStreet or similar handle?**
   - Need Twitter Developer account with elevated access
   - API v2 with OAuth 2.0 for user auth
   - **Who controls the bot account?**

### 🟡 Important — Need Answers Before Phase 2

3. **MoltCity governance integration — what decisions does governance control?**
   - Token launch approvals? Fee parameter changes? Blacklisting scam tokens?
   - **Or is MoltStreet independent initially?**

4. **Bonding curve vs direct Uniswap — which model first?**
   - Bankr style = straight to Uniswap v4 pool (via clanker)
   - Pump.fun style = bonding curve → migrate to DEX at market cap threshold
   - **Bonding curve is more viral but more complex**

### 🟢 Nice to Have — Can Decide Later

5. **Farcaster support — priority?** X-only first or also Farcaster?
6. **Open source strategy — when?** Day 1 or after MVP?
7. **Token metadata / branding** — auto-generate logos? IPFS?
8. **Bankr API deep dive** — map all endpoints from bankr.bot/api (we have `BANKR_API` key)

---

## Immediate Next Steps

1. ~~**Get Sowmay's answers**~~ ✅ — 9 core questions resolved (see Strategic Decisions above)
2. **Reverse-engineer bankr's fee structure** (`bankr.bot/api`) — match their fees
3. **Study clanker's integration API** — understand how bankr calls clanker, replicate it
4. **Build Twitter listener MVP** — parse `@MoltStreet launch $TICKER` mentions
5. **Build clanker bridge service** — integrate clanker for token deploy + Uniswap v4 pool
6. **Implement IP protection / anti-sybil** — rate limiting per user/IP
7. **Research ERC-8004** — understand agent identity standard for Phase 3 roadmap
8. **Set up custodial wallet system** — one wallet per Twitter user (still needs wallet tech decision)
9. **Deploy on Base Sepolia** — test end-to-end flow

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

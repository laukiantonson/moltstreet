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

MoltStreet builds its **own token deployer + Uniswap v4 LP hooks** — no clanker dependency. This gives us full control over fee hooks, LP management, and future features. Clanker's contracts were reviewed (nothing complex, lots of features like MEV protection) — we're building a stripped-down V1 with basic deploy + LP + fee hooks, then adding advanced features in V2. Wrapped with a superior social layer, MoltX ecosystem integration, and a roadmap toward agent-first features (ERC-8004).

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
         │                    │  Token Deployer       │ ← Custom ERC-20 factory (our own contracts)
         │                    │  /contracts/deployer/ │ ← Deploy token + create Uniswap v4 pool
         │                    │                       │ ← LP deposit with fee hooks (we earn fees)
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
                              │  /services/analytics/│ ← GeckoTerminal API (Uniswap v4 pools)
                              └─────────────────────┘

                              ┌─────────────────────┐
                              │  Fee Layer           │ ← Matches bankr's fee structure
                              │  /services/fees/     │ ← Fees → $MOLTX stakers
                              └─────────────────────┘
```

**Key difference vs bankr:** We own the entire stack — custom token deployer + LP hooks on Uniswap v4. Bankr depends on clanker (fragile). We control fees, LP, and can iterate on contract features independently. Thrilok (smart contract lead) is building V1: basic deployer + LP + fee hooks. Advanced features (MEV protection, etc.) come in V2.

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
| Token deployment | Depends on Clanker (Farcaster bot) | **Own deployer + Uniswap v4 LP hooks** — no clanker dependency |
| Social platform | X/Twitter only | X/Twitter + Farcaster + API |
| Trading | Launch only | Launch + buy/sell + portfolio |
| Agent support | Human users only | Human-first MVP → ERC-8004 agent identity (Phase 3) |
| Ecosystem | Standalone | MoltCity + MoltBook + $MOLTX |
| IP/Anti-sybil | ✅ Yes | ✅ Yes + IP protection + anti-sybil |
| Analytics/Indexing | Clanker indexing | GeckoTerminal (auto-indexes Uniswap v4 pools) |
| Fee structure | Their fee model | Match bankr fees initially |
| Revenue model | Unclear | Fees → $MOLTX stakers |
| Open source | No | Yes (planned) |

---

## Strategic Decisions (Resolved)

Sowmay's answers to the 9 core development questions (from Donald Pump group):

| # | Question | Decision | Implication |
|---|----------|----------|-------------|
| 1 | Fork clanker or build from scratch? | **~~Use clanker~~ → Build our own deployer** | Thrilok reviewed clanker contracts ("nothing complex, just lots of features"). Building custom token deployer + LP on Uniswap v4 with fee hooks as V1. Advanced features (MEV protection etc.) in V2. |
| 2 | Own Uniswap hook or clanker's? | **~~Clanker's~~ → Our own fee hooks** | Custom Uniswap v4 fee hooks — LP deposits earn us fees. Full control over fee structure. |
| 3 | LP model? | **Uniswap v4** (own contracts) | Direct pool creation via our deployer. LP deposit is where we earn revenue. |
| 4 | Agent-first or human-first? | **Human first** | MVP targets human users via X/Twitter; agent features (ERC-8004) come in Phase 3 |
| 5 | Compete with bankr or integrate? | **Compete** | MoltStreet is a direct competitor, not a bankr integration |
| 6 | Fee structure? | **Follow bankr's fee structure** | Match bankr's fees. Our own hooks give us direct control. |
| 7 | Indexing/Analytics? | **GeckoTerminal** | Since we deploy on Uniswap v4, GeckoTerminal auto-indexes our pools. Simplifies analytics dev. |
| 8 | ERC-8004? | **Yes, research** | Research ERC-8004 for agent identity — not MVP-blocking but on roadmap |
| 9 | Anti-sybil/IP protection? | **Yes, IP protection** | Implement IP-based rate limiting + anti-sybil measures |

### ⚡ PIVOT (Feb 10, 2025): Custom Deployer Instead of Clanker

Thrilok proposed building our own token deployer + LP hooks on Uniswap v4 instead of using clanker. Sowmay approved immediately. Key reasons:

- Clanker has "nothing complex, just lots of features like MEV" — we can build the core ourselves
- **V1**: Basic token deployer + LP creation on Uniswap v4 + fee hooks (we earn from LP deposits)
- **V2**: Advanced features (MEV protection, etc.) added iteratively
- **Advantage**: No clanker dependency. Full control over fees, LP, and contract upgrades.
- **Thirdweb** offered by Charan for token deployment, but Thrilok confirmed that part is trivial — the value is in LP creation + fee hooks.
- **Next need after contracts**: UI to see token + DEX details (GeckoTerminal can handle this)

### What This Means for Architecture

- **We ARE building a custom token deployer.** No clanker dependency — unlike bankr.
- **Custom Uniswap v4 fee hooks.** We control LP creation and earn fees directly.
- **GeckoTerminal for analytics.** Since we're on Uniswap v4, GeckoTerminal auto-indexes.
- **Human-first MVP.** ERC-8004 agent identity is Phase 3, not Phase 1.
- **Competitive advantage over bankr.** They depend on clanker. We own the stack.

---

## Tech Stack (Proposed)

```
Smart Contracts:      Foundry (Solidity) — Token deployer + Uniswap v4 LP hooks + fee hooks
                      Deployed on Base (Sepolia for testing)
Twitter Listener:     Node.js/TypeScript + Twitter API v2
Trading Engine:       TypeScript + Uniswap v4 SDK + Base RPC
Analytics:            GeckoTerminal API (auto-indexes Uniswap v4 pools)
Database:             PostgreSQL (user wallets, launches, trades)
Wallet Management:    ethers.js HD wallets or MPC (Privy / Turnkey) — TBD
Infrastructure:       Railway / Fly.io / VPS
Monitoring:           Grafana + custom dashboards
```

---

## Project Structure

```
moltstreet/
├── contracts/
│   ├── token-deployer/     # ERC-20 factory — custom token deployment
│   ├── lp-hooks/           # Uniswap v4 LP creation + fee hooks (revenue engine)
│   └── fee-splitter/       # Fee distribution to $MOLTX stakers
├── services/
│   ├── twitter-listener/   # X/Twitter mention monitoring + intent parsing
│   ├── trading-engine/     # Buy/sell execution via Uniswap v4
│   └── analytics/          # GeckoTerminal integration for token + DEX data
├── scripts/                # Deployment scripts, migrations
├── docs/                   # Architecture docs, API specs
└── README.md
```

---

## Open Development Questions

### ✅ Resolved (Sowmay's Decisions)

1. ~~**Fork clanker or build from scratch?**~~ → **Build our own.** Custom token deployer (Thrilok building V1).
2. ~~**Own Uniswap hook or clanker's?**~~ → **Our own hooks.** Custom Uniswap v4 fee hooks.
3. ~~**LP model?**~~ → **Uniswap v4** via our own contracts.
4. ~~**Agent-first or human-first?**~~ → **Human first.** Agent features in Phase 3.
5. ~~**Compete with bankr or integrate?**~~ → **Compete.** Direct competitor.
6. ~~**Fee structure?**~~ → **Follow bankr's fee structure.** Our own fee hooks give us direct control.
7. ~~**Indexing/Analytics?**~~ → **GeckoTerminal.** Uniswap v4 pools are auto-indexed. No custom indexer needed.
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

## Current Status (Feb 10, 2025)

**🔨 Active Development:**
- **Thrilok** is building the token deployer + Uniswap v4 LP hooks with fee hooks (V1)
- Contracts: basic token deploy → LP creation → fee collection
- After contracts: need UI for token + DEX details (GeckoTerminal integration)

**Key people:**
- **Thrilok** — Smart contract lead. Building deployer + LP hooks.
- **Sowmay** — Product lead. Approving decisions, sharing competitive intel from X.
- **Charan** — Offered thirdweb for token deployment (Thrilok said not needed for deploy, but potentially useful later).
- **Rohan** — Early contributor, helped map bankr→clanker architecture.
- **Kittu/Kaymas** — Group member, offered to add more people.

## Immediate Next Steps

1. ~~**Get Sowmay's answers**~~ ✅ — 9 core questions resolved
2. ~~**Study clanker's contracts**~~ ✅ — Thrilok reviewed. "Nothing complex, just lots of features like MEV."
3. 🔨 **Thrilok: Build token deployer + LP hooks** — V1 with basic features. IN PROGRESS.
4. **After contracts: Build UI** — Token + DEX details page (GeckoTerminal integration)
5. **Reverse-engineer bankr's fee structure** (`bankr.bot/api`) — calibrate our fee hooks
6. **Build Twitter listener MVP** — parse `@MoltStreet launch $TICKER` mentions
7. **Implement IP protection / anti-sybil** — rate limiting per user/IP
8. **Research ERC-8004** — understand agent identity standard for Phase 3 roadmap
9. **Set up custodial wallet system** — still needs wallet tech decision
10. **Deploy on Base Sepolia** — test end-to-end flow

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

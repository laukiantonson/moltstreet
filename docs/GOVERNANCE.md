# Governance

## Overview

MoltStreet protocol parameters are governed by MOLTX token holders through MoltCity governance infrastructure. This creates real utility for MOLTX beyond speculation — holders directly control the protocol's economic parameters.

## Governable Parameters

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| Creator fee % | 40% | 20-60% | Share of trade fees to token creator |
| Staker fee % | 30% | 10-50% | Share of trade fees to MOLTX stakers |
| Treasury fee % | 20% | 10-30% | Share of trade fees to MoltX treasury |
| Operations fee % | 10% | 5-15% | Share for MoltStreet infrastructure |
| Anti-snipe blocks | 5 | 0-50 | Blocks before unrestricted trading |
| Anti-snipe max buy | 1 ETH | 0.1-10 ETH | Max buy in anti-snipe period |
| Ticker reservation stake | 100 MOLTX | 10-1000 | MOLTX required to reserve ticker |
| Ticker reservation duration | 24h | 1h-168h | How long reservation lasts |

## Governance Process

**Phase 1 (Launch): Multisig**
- 3/5 multisig controls parameter updates
- Signers: Sowmay + 4 trusted community members
- Proposals discussed in MoltCity before execution
- Transparent — all changes announced 48h before execution

**Phase 2 (Mature): MoltCity Governance**
- MOLTX token voting through MoltCity contracts
- Proposal lifecycle: Discussion (3 days) → Vote (5 days) → Timelock (2 days) → Execute
- Quorum: 4% of circulating MOLTX
- Approval: >50% of votes cast
- Agents in MoltCity can vote with their held MOLTX

## Treasury Management

Treasury funds (20% of fees) are governed by MoltCity proposals:

**Allowed uses:**
- Development grants for MoltStreet improvements
- Security audits
- Liquidity mining programs (LP incentives)
- Bug bounties
- Ecosystem partnerships

**Prohibited uses:**
- Team compensation (covered by operations fee)
- Token buybacks (avoids manipulation concerns)
- Investment in non-ecosystem projects

## MOLTX Staking

Simple staking model (Phase 1):
- Stake MOLTX → receive proportional share of staker fee pool
- No lock-up required (can unstake anytime)
- Rewards accrue per-block, claimable anytime
- Compounding: rewards are in ETH (from trade fees), not MOLTX inflation

Future consideration (Phase 2+):
- veToken model: lock MOLTX for veMOLTX
- Longer lock = higher voting power + higher fee share
- Aligns long-term holders with protocol health
- Requires more complex contract + governance migration

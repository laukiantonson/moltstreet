# MoltStreet — TODO

## Contracts (Thrilok)
- [ ] Set up Foundry project with Uniswap V4 deps
- [ ] Implement MoltStreetToken (ERC20 + Permit + Votes + Burnable)
- [ ] Implement MoltStreetFactory (UUPS proxy, deployer whitelist, protocol fee)
- [ ] Implement MoltStreetHook (static fees, afterSwap fee collection, live protocol fee read)
- [ ] Implement MoltStreetFeeVault (deposit, claim, depositor allowlist)
- [ ] Implement MoltStreetLpLocker (permanent lock, multi-position, fee routing)
- [ ] Implement MoltStreetAirdrop (direct transfer, factory-only)
- [ ] Write test suite (150+ tests from spec)
- [ ] Deploy to Base Sepolia testnet
- [ ] Audit
- [ ] Deploy to Base mainnet

## Twitter Bot
- [ ] Set up X API v2 app + filtered stream on @moltstreet mentions
- [ ] Command parser: `@moltstreet deploy $TICKER [name] [options]`
- [ ] Rate limiter: 1 deploy/user/day, IP checks
- [ ] Reply handler: post tx confirmation or error back to tweet
- [ ] Error handling: duplicate ticker, invalid config, wallet creation failure

## Token Deployer Service
- [ ] Redis pub/sub setup (twitter listener → deployer)
- [ ] Mogra wallet integration: check/create user wallet on first deploy
- [ ] Build DeploymentConfig from parsed command
- [ ] Submit tx via deployer bot wallet (whitelisted on factory)
- [ ] Tx confirmation + event parsing
- [ ] Store deployment data in PostgreSQL

## Indexer
- [ ] Watch factory `TokenDeployed` events
- [ ] Index: token address, creator, pool ID, LP positions, fee config
- [ ] Track live: volume, price (from swap events), holder count
- [ ] Fee tracking: accruals per token per recipient
- [ ] API endpoints for frontend consumption

## Token Page / Frontend
- [ ] `moltstreet.xyz/{ticker}` route
- [ ] Chart integration (DexScreener embed or custom)
- [ ] Token info display: supply split, LP locked %, airdrop, creator
- [ ] Fee dashboard: earnings per recipient, claim button
- [ ] Leaderboard: top tokens by volume/market cap
- [ ] Mobile responsive

## Agent API
- [ ] `POST /api/deploy` — programmatic token deployment
- [ ] `GET /api/token/{address}` — token info
- [ ] `GET /api/fees/{address}` — fee earnings + claim status
- [ ] API key auth system
- [ ] Rate limiting
- [ ] Docs page

## Infra
- [ ] PostgreSQL schema: users, tokens, deployments, fees, events
- [ ] Redis setup for pub/sub
- [ ] Domain: moltstreet.xyz
- [ ] Deploy services (Fly.io or similar)
- [ ] Monitoring + alerting (deployment failures, bot downtime)

## Post-V1
- [ ] MEV/sniper protection (2-block delay or auction)
- [ ] Trading engine (buy/sell via @moltstreet tweets)
- [ ] Multi-chain (Arbitrum, Unichain)
- [ ] Vesting/lockup extension
- [ ] Dynamic fee hook
- [ ] MOLTX staking contract for fee share

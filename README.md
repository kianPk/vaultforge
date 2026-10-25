# VaultForge

**ERC-4626 yield vault** with strategy allocation, performance fees, role-gated ops, and guardian pause — built with Foundry + OpenZeppelin.

[![CI](https://github.com/kianPk/vaultforge/actions/workflows/ci.yml/badge.svg)](https://github.com/kianPk/vaultforge/actions/workflows/ci.yml)
[![Demo](https://img.shields.io/badge/Demo-kianpk.github.io%2Fvaultforge-10b981?style=for-the-badge)](https://kianpk.github.io/vaultforge/)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636?style=for-the-badge&logo=solidity)](https://github.com/kianPk/vaultforge)
[![Foundry](https://img.shields.io/badge/Foundry-forge-000000?style=for-the-badge)](https://book.getfoundry.sh/)

> Lab / portfolio protocol — audit before any mainnet use.

## Architecture

```text
User ──deposit/mint──▶ VaultForge (ERC-4626 + AccessControl + Pausable)
                           │
                           ├─ allocate / recall ──▶ IStrategy
                           │                         └─ MockYieldStrategy
                           └─ harvest() → performance fee shares → feeRecipient
```

| Piece | Role |
|-------|------|
| `VaultForge` | Share token, NAV via `totalAssets()`, fee mint on harvest |
| `IStrategy` | Deposit / withdraw / harvest surface |
| `MockYieldStrategy` | Demo yield strategy (bps per harvest) |
| Roles | `DEFAULT_ADMIN`, `STRATEGIST`, `GUARDIAN` |

## Quick start

```bash
forge install
forge test -vv
forge coverage
```

```bash
# fuzz + unit
forge test --match-contract VaultForgeTest
```

## Also in this release

- **Strategy cap** — `setStrategyCap` limits deployed NAV; enforced on `allocate` / `rebalance`
- Deposit cap + debt-ratio `rebalance()`
- Share price + high-water mark tracking
- Strategist allocate / recall / harvest with performance fees

## Key flows

1. **Deposit** → mint vault shares 1:1 on empty vault  
2. **Allocate** → strategist pushes idle liquidity into strategy  
3. **Harvest** → profit booked; performance fee minted as shares to `feeRecipient`  
4. **Withdraw / redeem** → pulls from strategy if idle is short  
5. **Pause** → guardian freezes deposits/mints/withdraws/redeems  

## Stack

```text
Solidity 0.8.24 · Foundry · OpenZeppelin ERC-4626 / AccessControl / Pausable
```

## License

MIT © [kianPk](https://github.com/kianPk)

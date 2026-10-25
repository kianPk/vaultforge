# Contributing

Thanks for helping improve VaultForge.

## Development

```bash
forge install
forge test -vv
forge fmt
```

## Pull requests

1. Fork and branch from `main`
2. Add or update tests for behavior changes
3. Run `forge test` and `forge fmt` before opening a PR
4. Describe the change and link any related issues

## Style

- Solidity `0.8.24`, OpenZeppelin patterns where applicable
- Prefer explicit errors and events over bare `require` strings

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Tooling

- For one-off tools: use `npx`, `uv`, or `nix run` if not installed locally
- Dev environment: use `shell.nix`
- Haskell: Stack with `nix: true` in stack.yaml, choose GHC version that minimizes rebuilds

## Commits

- Commit after completing each task
- Use conventional commits format: `type(scope): description`
  - Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `build`
  - Scope: module or area affected (e.g., `types`, `transport`, `client`)
- No Claude attribution in commits
- Keep commits atomic - one logical change per commit

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Tooling

- For one-off tools: use `npx`, `uv`, or `nix run` if not installed locally
- Dev environment: use `shell.nix`
- Haskell: Stack with `nix: true` in stack.yaml, choose GHC version that minimizes rebuilds

## Haskell OpenSpec Workflow

**Haskell OpenSpec tasks must be delegated to a Haskell subagent** (Claude Sonnet). Do not implement Haskell tasks directly. Instead, use the Task tool to spawn a Sonnet subagent with:
- `subagent_type: "general-purpose"` or specialized agent if available
- `model: "sonnet"`
- Clear task description with context from artifacts

## Commits for Haskell Tasks

When implementing Haskell tasks (via subagent):
- **Commit after every completed task** - don't wait for multiple tasks
- Use conventional commits format: `type(scope): description`
  - Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `build`
  - Scope: module or area affected (e.g., `types`, `transport`, `client`)
- **No Claude attribution** - no "Co-Authored-By" in commit messages
- Keep commits atomic - one logical change per commit
- Example: `feat(types): implement Get instance for boolean decoding`

# Haskell Development Skills

## Build & Run

```bash
# Build
stack build

# Build with file watching
stack build --file-watch

# Run tests
stack test

# Run a single test suite
stack test :test-suite-name

# Run specific test (using tasty pattern)
stack test --test-arguments '-p "pattern"'

# REPL
stack ghci

# Run executable
stack exec <executable-name>
```

## Code Quality

```bash
# Format code
stack exec -- ormolu --mode inplace <file.hs>

# Lint
stack exec -- hlint <file.hs>

# Type check without building
stack build --fast --pedantic
```

## Stack + Nix Integration

stack.yaml should have:
```yaml
nix:
  enable: true
  packages: [zlib, pcre]  # system deps as needed
```

shell.nix provides system dependencies; Stack handles Haskell deps.

**Running commands outside nix-shell**:
```bash
# Use nix-shell --run for one-off commands
nix-shell --run "stack build"
nix-shell --run "stack test"

# Or enter nix-shell first
nix-shell
stack test
```

Never use cabal directly - always use stack.

## Common Patterns

- Use `Text` over `String` for text data
- Prefer `lens` for record access in complex types
- Use `mtl` style for effect stacks
- Binary parsing: `binary` or `cereal` packages
- Network: `network` package for low-level sockets

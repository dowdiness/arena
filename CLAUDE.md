# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A MoonBit arena allocator library (`dowdiness/arena`) designed for manual memory management in domains where MoonBit's default Perceus (reference-counting) GC is insufficient: real-time DSP, parsers, CRDTs, and incremental computation. The project is in early stages — currently contains placeholder functions (`fib`, `sum`) with the arena implementation planned per the design documents.

## Build & Development Commands

```bash
moon check          # Lint/typecheck
moon build          # Build the project
moon test           # Run all tests
moon test --update  # Run tests and update snapshot expectations
moon fmt            # Format code
moon info           # Update .mbti interface files
moon info && moon fmt  # Standard pre-commit workflow: update interfaces then format
moon run cmd/main   # Run the main executable
```

After making changes, always run `moon info && moon fmt` and check `.mbti` diffs to verify whether your changes affect the public API.

Use `moon coverage analyze > uncovered.log` to check test coverage.

## MoonBit Coding Conventions

- Code is organized in **block style**: each block is separated by `///|`. Block order within a file is irrelevant.
- Tests use `inspect(value, content="expected")` for snapshot testing. Write `inspect(value)` first, then run `moon test --update` to fill in expected values. Only use `assert_eq` inside loops where snapshots vary.
- Labelled arguments use `~` syntax (e.g., `data~`). Optional labelled arguments use `?` with defaults (e.g., `start? : Int = 0`). Punning with `?` is idiomatic (e.g., `sum(data=array, length?)`).
- Keep deprecated code in `deprecated.mbt` files.

## Architecture (Planned)

The library follows a 3-layer architecture with an additional domain layer on top:

- **Layer 1 (Physical Memory)**: `BumpAllocator` trait with two implementations — `MbBump` (FixedArray[Byte], all backends) and `CFFIBump` (C malloc, native only, GC-free)
- **Layer 2 (Generic Arena)**: `Arena` struct with generational indices (`Ref`) for use-after-reset detection. `GenStore` trait for per-slot generation tracking. Reset is O(1) via lazy invalidation.
- **Layer 3 (Typed Arena)**: `Storable` trait for fixed-size serialization. `TypedRef[T]` phantom-typed references. Manual specialization pattern (e.g., `F64Arena`, `AudioArena`) since MoonBit lacks bounded type parameters on structs.
- **Domain Layer**: `AudioBufferPool` (DSP), `ASTArena` (parser), `CRDTOpPool`, `MemoTable` (incr)

Backend switching uses enum dispatch (`BumpImpl`, `GenStoreImpl`) with constructor variants `Arena::new_debug` (all MoonBit), `Arena::new_release` (all C-FFI), `Arena::new_hybrid`.

See `memory-management-design.md` (English) and `memory-management-design-ja.md` (Japanese) for the full design document including formal semantics, safety levels, and implementation roadmap.

## Project Structure

- Root package (`/`): library code (`arena.mbt`, tests in `arena_test.mbt`)
- `cmd/main/`: executable that imports the root package as `@lib`
- `moon.mod.json`: module definition (`dowdiness/arena`)
- `moon.pkg.json`: package config (per directory, lists dependencies)

## Git Hooks

Pre-commit hook runs `moon check`. To enable:
```bash
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
```

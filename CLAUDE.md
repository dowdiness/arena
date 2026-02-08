# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A MoonBit arena allocator library (`dowdiness/arena`) designed for manual memory management in domains where MoonBit's default Perceus (reference-counting) GC is insufficient: real-time DSP, parsers, CRDTs, and incremental computation.

**Phase 2 is complete**: trait-abstracted generic arena (`Arena[B, G]`) with both pure MoonBit and C-FFI backends. The root package runs on all backends (wasm-gc, JS, native); the `cffi/` sub-package provides a native-only C-backed implementation. See `ROADMAP.md` for implementation status and next phases.

## Build & Development Commands

```bash
moon check                    # Lint/typecheck (default wasm-gc target)
moon check --target native    # Lint/typecheck including cffi package
moon build                    # Build the project
moon build --target native    # Build including native C-FFI backend
moon test                     # Run root package tests (wasm-gc)
moon test --target native     # Run all tests including cffi (native)
moon test --update            # Run tests and update snapshot expectations
moon fmt                      # Format code
moon info                     # Update .mbti interface files (wasm-gc)
moon info --target native     # Update .mbti including cffi package
moon info && moon fmt         # Standard pre-commit workflow: update interfaces then format
moon run cmd/main             # Run the main executable
```

After making changes, always run `moon info && moon fmt` and check `.mbti` diffs to verify whether your changes affect the public API.

Use `moon coverage analyze > uncovered.log` to check test coverage.

## MoonBit Coding Conventions

- Code is organized in **block style**: each block is separated by `///|`. Block order within a file is irrelevant.
- Tests use `inspect(value, content="expected")` for snapshot testing. Write `inspect(value)` first, then run `moon test --update` to fill in expected values. Only use `assert_eq` inside loops where snapshots vary.
- Labelled arguments use `~` syntax (e.g., `data~`). Optional labelled arguments use `?` with defaults (e.g., `start? : Int = 0`). Punning with `?` is idiomatic (e.g., `sum(data=array, length?)`).
- Keep deprecated code in `deprecated.mbt` files.

## Architecture

The library follows a 3-layer architecture with an additional domain layer on top:

- **Layer 1 (Physical Memory)** [Phase 2: implemented]: `BumpAllocator` trait with two implementations — `MbBump` (pure MoonBit, all backends) and `CFFIBump` (C-FFI, native only). Overflow-safe alignment and bounds-checked typed read/write.
- **Layer 2 (Generic Arena)** [Phase 2: implemented]: `Arena[B, G]` generic struct with trait-constrained type parameters. `GenStore` trait with `MbGenStore` (pure MoonBit) and `CGenStore` (C-FFI, native only). Generational indices (`Ref`) for use-after-reset detection. O(1) reset via lazy invalidation. MoonBit monomorphizes the generics — zero dispatch overhead.
- **Layer 3 (Typed Arena)** [Phase 3: planned]: `Storable` trait for fixed-size serialization. `TypedRef[T]` phantom-typed references. Manual specialization pattern (e.g., `F64Arena`, `AudioArena`) since MoonBit lacks bounded type parameters on structs.
- **Domain Layer** [Phase 4: planned]: `AudioBufferPool` (DSP), `ASTArena` (parser), `CRDTOpPool`, `MemoTable` (incr)

Backend switching uses generic type parameters with monomorphization: `Arena[MbBump, MbGenStore]` (all MoonBit, all backends) vs `Arena[CFFIBump, CGenStore]` (C-FFI, native only). Constructors: `Arena::new` (convenience, MbBump), `cffi.new_arena` (convenience, CFFIBump), `Arena::new_with` (generic, any backend).

See `memory-management-design.md` (English) and `memory-management-design-ja.md` (Japanese) for the full design document including formal semantics, safety levels, and implementation roadmap.

## Project Structure

- Root package (`/`): library code split across files:
  - `arena.mbt` — `Arena[B, G]` generic struct and methods
  - `bump_allocator.mbt` — `BumpAllocator` trait definition
  - `gen_store_trait.mbt` — `GenStore` trait definition
  - `mb_bump.mbt` — `MbBump` struct + `BumpAllocator` impl
  - `mb_gen_store.mbt` — `MbGenStore` struct + `GenStore` impl
  - `ref.mbt` — `Ref` generational index struct
  - `*_test.mbt` — blackbox tests, `*_wbtest.mbt` — whitebox tests
- `cffi/`: native-only sub-package (`dowdiness/arena/cffi`):
  - `c_bump.c` / `c_bump.mbt` — `CFFIBump` C-FFI bump allocator
  - `c_gen.c` / `c_gen.mbt` — `CGenStore` C-FFI generation storage
  - `cffi.mbt` — `new_arena()` convenience constructor
  - `*_test.mbt` — tests (mirroring root package test patterns)
  - `moon.pkg.json` — native-only via `targets` conditional compilation
- `cmd/main/`: executable that imports the root package as `@lib`
- `moon.mod.json`: module definition (`dowdiness/arena`)
- `moon.pkg.json`: package config (imports `moonbitlang/core/int`)

## Git Hooks

Pre-commit hook runs `moon check`. To enable:
```bash
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
```

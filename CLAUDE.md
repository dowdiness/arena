# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A MoonBit arena allocator library (`dowdiness/arena`) designed for manual memory management, currently focused on real-time DSP. The generic core (`Arena[B, G]`, `BumpAllocator`, `GenStore`) is domain-agnostic and can support parsers, CRDTs, and incremental computation in the future.

**Phase 5 (Hybrid C-FFI Lifetime Management) is complete**: trait-abstracted generic arena (`Arena[B, G]`) with both pure MoonBit and C-FFI backends, type-safe wrappers (`Storable` trait, `TypedRef[T]`, specialized arenas `F64Arena`, `I32Arena`, `AudioArena`), DSP domain wrapper `AudioBufferPool[B, G]`, and automatic finalization for C-FFI via `moonbit_make_external_object`. Next: dogfooding in a real DSP pipeline. The root package runs on all backends (wasm-gc, JS, native); the `cffi/` sub-package provides a native-only C-backed implementation. See `ROADMAP.md` for implementation status.

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
moon bench                    # Run MbBump benchmarks (wasm-gc)
moon bench --target native    # Run all benchmarks including CFFIBump
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

- **Layer 1 (Physical Memory)** [Phase 2: implemented, Phase 5: hybrid lifetime]: `BumpAllocator` trait with two implementations — `MbBump` (pure MoonBit, all backends) and `CFFIBump` (C-FFI, native only). Overflow-safe alignment and bounds-checked typed read/write (int32, double, byte). Contract is explicit: successful `alloc` must imply writable allocated range until `reset`. C-FFI objects use `moonbit_make_external_object` for automatic finalization (RC-managed); `destroy()` remains for deterministic early release. All hot-path operations use `#borrow` — zero RC overhead.
- **Layer 2 (Generic Arena)** [Phase 2: implemented]: `Arena[B, G]` generic struct with trait-constrained type parameters. `GenStore` trait with `MbGenStore` (pure MoonBit) and `CGenStore` (C-FFI, native only). Generational indices (`Ref`) for use-after-reset detection. O(1) reset via lazy invalidation. MoonBit monomorphizes the generics — zero dispatch overhead.
- **Layer 3 (Typed Arena)** [Phase 3: implemented]: `Storable` trait for fixed-size serialization. `TypedRef[T]` phantom-typed references. Manually specialized arenas (`F64Arena[B, G]`, `I32Arena[B, G]`, `AudioArena[B, G]`) bypass Storable for zero-copy access via Arena's typed accessors. Typed `alloc` aborts on post-alloc write failure (contract violation); `set` remains recoverable (`Bool`).
- **Domain Layer** [Phase 4: DSP focus]: `AudioBufferPool[B, G]` (implemented) — multi-sample buffer pool with `BufferRef`, frame/channel-indexed sample access, per-callback lifecycle. Other domain wrappers (ASTArena, CRDTOpPool, MemoTable) deferred to future improvements.

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
  - `storable.mbt` — `Storable` trait + `Double`/`Int` impls
  - `typed_ref.mbt` — `TypedRef[T]` phantom-typed wrapper
  - `audio_frame.mbt` — `AudioFrame` struct + `Storable` impl
  - `f64_arena.mbt` — `F64Arena[B, G]` specialized arena for `Double`
  - `i32_arena.mbt` — `I32Arena[B, G]` specialized arena for `Int`
  - `audio_arena.mbt` — `AudioArena[B, G]` specialized arena for `AudioFrame`
  - `buffer_ref.mbt` — `BufferRef` newtype wrapping `Ref` for audio buffers
  - `audio_buffer_pool.mbt` — `AudioBufferPool[B, G]` DSP buffer pool
  - `*_test.mbt` — blackbox tests, `*_wbtest.mbt` — whitebox tests
  - `bench_*_test.mbt` — benchmarks (`moon bench`)
- `cffi/`: native-only sub-package (`dowdiness/arena/cffi`):
  - `c_bump.c` / `c_bump.mbt` — `CFFIBump` C-FFI bump allocator
  - `c_gen.c` / `c_gen.mbt` — `CGenStore` C-FFI generation storage
  - `cffi.mbt` — `new_arena()` convenience constructor
  - `*_test.mbt` — tests (mirroring root package test patterns)
  - `bench_*_test.mbt` — CFFIBump/CGenStore benchmarks
  - `moon.pkg.json` — native-only via `targets` conditional compilation
- `cmd/main/`: executable that imports the root package as `@lib`
- `moon.mod.json`: module definition (`dowdiness/arena`)
- `moon.pkg.json`: package config (imports `moonbitlang/core/int`, `moonbitlang/core/bench`)

## Git Hooks

Pre-commit hook runs `moon check`. To enable:
```bash
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
```

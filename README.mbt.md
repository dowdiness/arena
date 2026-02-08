# dowdiness/arena

A MoonBit arena allocator library for manual memory management in domains where reference-counting GC is insufficient: real-time DSP, parsers, CRDTs, and incremental computation.

Pure MoonBit implementation runs on all backends (wasm-gc, JS, native). Optional C-FFI backend for native targets provides zero-overhead allocation via `cffi/` sub-package.

## Quick Start

```moonbit
let arena = @arena.Arena::new(1024, 16)  // 1024 slots, 16 bytes each
let ref = arena.alloc().unwrap()

arena.write_double(ref, 0, 3.14) |> ignore
arena.write_int32(ref, 8, 42) |> ignore

let val = arena.read_double(ref, 0)  // Some(3.14)

arena.reset()  // O(1) — invalidates all refs
arena.is_valid(ref)  // false — stale ref detected
```

## Features

- **Generic arena** — `Arena[B, G]` with trait-based backends, monomorphized for zero dispatch overhead
- **Dual backends** — pure MoonBit (`MbBump`/`MbGenStore`, all platforms) and C-FFI (`CFFIBump`/`CGenStore`, native only)
- **Bump allocation** backed by `FixedArray[Byte]` or C `malloc` — fast, linear allocation
- **Generational indices** — `Ref` carries a generation tag for use-after-reset detection
- **O(1) reset** — lazy invalidation via generation counter, no per-slot cleanup
- **Typed read/write** — `Int32` and `Double` access with bounds checking
- **Overflow-safe arithmetic** — all allocation and bounds checks handle integer overflow
- **No panics on bad input** — public API returns `Option`/`Bool` instead of crashing
- **FFI safety** — null-pointer checks, destroy-safety flags, bounds validation before FFI boundary

## API

### Arena[B, G]

| Method | Signature | Description |
|--------|-----------|-------------|
| `Arena::new` | `(Int, Int) -> Arena[MbBump, MbGenStore]` | Create arena with slot count and slot size (MbBump backend) |
| `Arena::new_with` | `[B, G](B, G, Int, Int) -> Arena[B, G]` | Create arena with custom backends |
| `Arena::alloc` | `(Self) -> Ref?` | Allocate one slot, returns generational ref |
| `Arena::is_valid` | `(Self, Ref) -> Bool` | Check if ref is still valid |
| `Arena::reset` | `(Self) -> Unit` | Invalidate all refs (O(1)) |
| `Arena::write_int32` | `(Self, Ref, Int, Int) -> Bool` | Write Int32 at field offset |
| `Arena::read_int32` | `(Self, Ref, Int) -> Int?` | Read Int32 at field offset |
| `Arena::write_double` | `(Self, Ref, Int, Double) -> Bool` | Write Double at field offset |
| `Arena::read_double` | `(Self, Ref, Int) -> Double?` | Read Double at field offset |

### Traits

| Trait | Methods | Implementations |
|-------|---------|-----------------|
| `BumpAllocator` | alloc, reset, capacity, used, write/read int32/double | `MbBump`, `CFFIBump` |
| `GenStore` | get, set, length | `MbGenStore`, `CGenStore` |

### cffi (native only)

| Function | Signature | Description |
|----------|-----------|-------------|
| `new_arena` | `(Int, Int) -> Arena[CFFIBump, CGenStore]` | Create arena with C-FFI backends |
| `CFFIBump::destroy` | `(Self) -> Unit` | Free native memory (idempotent) |
| `CGenStore::destroy` | `(Self) -> Unit` | Free native memory (idempotent) |

## Build

```bash
moon check                    # Typecheck (wasm-gc)
moon check --target native    # Typecheck including cffi
moon build                    # Build
moon test                     # Run root tests (36 tests, wasm-gc)
moon test --target native     # Run all tests including cffi (71 tests)
moon run cmd/main             # Run demo
```

## Status

Phase 2 (Backend Abstraction & C-FFI) is complete. See `ROADMAP.md` for the full implementation plan including typed arenas and domain integrations.

## License

Apache-2.0

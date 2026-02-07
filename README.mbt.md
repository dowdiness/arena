# dowdiness/arena

A MoonBit arena allocator library for manual memory management in domains where reference-counting GC is insufficient: real-time DSP, parsers, CRDTs, and incremental computation.

Pure MoonBit implementation — runs on all backends (wasm-gc, JS, native).

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

- **Bump allocation** backed by `FixedArray[Byte]` — fast, linear allocation
- **Generational indices** — `Ref` carries a generation tag for use-after-reset detection
- **O(1) reset** — lazy invalidation via generation counter, no per-slot cleanup
- **Typed read/write** — `Int32` and `Double` access with bounds checking
- **Overflow-safe arithmetic** — all allocation and bounds checks handle integer overflow
- **No panics on bad input** — public API returns `Option`/`Bool` instead of crashing

## API

### Arena

| Method | Signature | Description |
|--------|-----------|-------------|
| `Arena::new` | `(Int, Int) -> Arena` | Create arena with slot count and slot size |
| `Arena::alloc` | `(Self) -> Ref?` | Allocate one slot, returns generational ref |
| `Arena::is_valid` | `(Self, Ref) -> Bool` | Check if ref is still valid |
| `Arena::reset` | `(Self) -> Unit` | Invalidate all refs (O(1)) |
| `Arena::write_int32` | `(Self, Ref, Int, Int) -> Bool` | Write Int32 at field offset |
| `Arena::read_int32` | `(Self, Ref, Int) -> Int?` | Read Int32 at field offset |
| `Arena::write_double` | `(Self, Ref, Int, Double) -> Bool` | Write Double at field offset |
| `Arena::read_double` | `(Self, Ref, Int) -> Double?` | Read Double at field offset |

### MbBump (low-level bump allocator)

| Method | Signature | Description |
|--------|-----------|-------------|
| `MbBump::new` | `(Int) -> MbBump` | Create bump allocator with byte capacity |
| `MbBump::alloc` | `(Self, Int, Int) -> Int?` | Allocate size bytes with alignment |
| `MbBump::reset` | `(Self) -> Unit` | Reset offset to 0 |

## Build

```bash
moon check          # Typecheck
moon build          # Build
moon test           # Run tests (33 tests)
moon run cmd/main   # Run demo
```

## Status

Phase 1 (Minimal Viable Arena) is complete. See `ROADMAP.md` for the full implementation plan including C-FFI backends, typed arenas, and domain integrations.

## License

Apache-2.0

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
- **Typed arenas** — `F64Arena`, `I32Arena`, `AudioArena` with phantom-typed `TypedRef[T]` references
- **AudioBufferPool** — DSP buffer pool with frame/channel-indexed sample access and per-callback lifecycle
- **Storable trait** — user-extensible byte-array serialization for custom types
- **Typed read/write** — `Int32`, `Double`, and `Byte` access with bounds checking
- **Overflow-safe arithmetic** — all allocation and bounds checks handle integer overflow
- **Strict allocator contract** — typed arenas abort on post-alloc write failures (contract violation)
- **Recoverable API failures** — stale/invalid access returns `Option`/`Bool`
- **FFI safety** — automatic finalization via `moonbit_make_external_object`, destroy-safety flags, bounds validation before FFI boundary

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
| `BumpAllocator` | alloc, reset, capacity, used, write/read int32/double/byte | `MbBump`, `CFFIBump` |
| `GenStore` | get, set, length | `MbGenStore`, `CGenStore` |
| `Storable` | byte_size, write_bytes, read_bytes | `Double`, `Int`, `AudioFrame` |

`BumpAllocator` contract: if `alloc` succeeds, writes/reads within the allocated
slot must succeed until `reset`. Typed arenas enforce this and abort on violation.

### Typed Arenas

| Type | Value type | Slot size | Key methods |
|------|-----------|-----------|-------------|
| `F64Arena[B, G]` | `Double` | 8 | `alloc`, `get`, `set`, `reset`, `is_valid` |
| `I32Arena[B, G]` | `Int` | 4 | `alloc`, `get`, `set`, `reset`, `is_valid` |
| `AudioArena[B, G]` | `AudioFrame` | 16 | `alloc`, `get`, `set`, `reset`, `is_valid` |

Typed arenas return `TypedRef[T]` instead of `Ref`, preventing type confusion at compile time.
`alloc` returns `None` only for allocation exhaustion and aborts if backend initialization
write fails after a successful alloc (contract violation). `get`/`set` remain recoverable
(`None`/`false`) for stale or invalid references.

| Type | Fields |
|------|--------|
| `TypedRef[T]` | `inner : Ref` (phantom-typed) |
| `AudioFrame` | `left : Double`, `right : Double` |

### AudioBufferPool[B, G]

DSP buffer pool for real-time audio. Each buffer holds `frames_per_buffer * channels` interleaved `Double` samples.

| Method | Signature | Description |
|--------|-----------|-------------|
| `AudioBufferPool::new` | `(Int, Int, Int) -> AudioBufferPool[MbBump, MbGenStore]` | Create pool (frames_per_buffer, channels, buffer_count) |
| `AudioBufferPool::new_with` | `[B, G](B, G, Int, Int, Int) -> AudioBufferPool[B, G]` | Create with custom backends |
| `AudioBufferPool::alloc` | `(Self) -> BufferRef?` | Allocate one buffer (no initialization) |
| `AudioBufferPool::write_sample` | `(Self, BufferRef, Int, Int, Double) -> Bool` | Write sample at (frame, channel) |
| `AudioBufferPool::read_sample` | `(Self, BufferRef, Int, Int) -> Double?` | Read sample at (frame, channel) |
| `AudioBufferPool::reset` | `(Self) -> Unit` | Invalidate all BufferRefs (O(1)) |
| `AudioBufferPool::is_valid` | `(Self, BufferRef) -> Bool` | Check if BufferRef is still valid |

| Type | Fields |
|------|--------|
| `BufferRef` | `inner : Ref` (audio buffer reference) |

Per-callback lifecycle: `reset()` → `alloc()` → `write_sample()` → `read_sample()` → callback returns.

### cffi (native only)

| Function | Signature | Description |
|----------|-----------|-------------|
| `new_arena` | `(Int, Int) -> Arena[CFFIBump, CGenStore]` | Create arena with C-FFI backends |
| `CFFIBump::destroy` | `(Self) -> Unit` | Free native memory early (optional, idempotent) |
| `CGenStore::destroy` | `(Self) -> Unit` | Free native memory early (optional, idempotent) |

**Lifetime management:** C-FFI objects use `moonbit_make_external_object` for
automatic finalization — native memory is freed when the last MoonBit reference
is dropped. `destroy()` is optional and available for deterministic early release
(e.g., audio engine reconfiguration). Calling `destroy()` then letting the
finalizer run is safe (no double-free). All hot-path operations use `#borrow`,
so there is zero RC overhead on the data path.

## Build

```bash
moon check                    # Typecheck (wasm-gc)
moon check --target native    # Typecheck including cffi
moon build                    # Build
moon test                     # Run root tests (88 tests, wasm-gc)
moon test --target native     # Run all tests including cffi (149 tests)
moon bench                    # Run MbBump benchmarks (wasm-gc)
moon bench --target native    # Run all benchmarks including CFFIBump
moon run cmd/main             # Run demo
```

## Benchmarks

Benchmarks verify the documented performance claims. Run with `moon bench --target native`.

| Claim | Verified | Evidence |
|-------|----------|----------|
| Reset-only baseline is tiny | Yes | Empty-arena `reset` benchmark is near 0 µs |
| Reset+refill cost scales with alloc count | Yes | 100-slot cycle is much faster than 10000-slot cycle |
| Zero dispatch overhead | Yes | Arena alloc cycle: MbBump ~12 µs vs CFFIBump ~12 µs |
| Fast linear allocation | Yes | 1000 bump allocs in ~7 µs (MbBump, native) |

Reset methodology:
- `reset baseline (empty arena)` benchmarks time `reset()` on an empty arena.
- `reset+refill cycle` benchmarks time `reset(); alloc*N` to keep each iteration in a consistent non-empty-state scenario.
- `reset-only complexity sweep (monotonic clock)` measures only `reset()` for `N=0/100/1000/10000`, with refill done outside the timed window.

**Bump allocation throughput (1000 ops, native):**

| Operation | MbBump | CFFIBump |
|-----------|--------|----------|
| alloc (8B, align=1) | ~7 µs | ~8 µs |
| int32 read/write | ~12 µs | ~10 µs |
| double read/write | ~15 µs | ~10 µs |

See `ROADMAP.md` §2.x for full benchmark results and methodology.

## Status

Phase 5 (Hybrid C-FFI Lifetime Management) is complete. C-FFI objects auto-finalize via `moonbit_make_external_object`; `destroy()` is optional for deterministic early release. See `ROADMAP.md` for the full implementation plan including remaining domain integrations.

## License

Apache-2.0

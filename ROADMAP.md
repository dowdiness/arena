# Implementation Roadmap

Based on the design in `memory-management-design.md` (§12).

## Current State

**Phase 4.1 (AudioBufferPool) is complete.** The DSP domain wrapper is
implemented on top of the generic arena. `AudioBufferPool[B, G]` provides
multi-sample buffer management for real-time DSP: `BufferRef`-indexed buffers
with frame/channel sample access, overflow-safe construction, and per-callback
lifecycle (reset → alloc → write → read). The `BumpAllocator` trait now also
includes byte-level read/write (`write_byte`/`read_byte`). Next: hybrid C-FFI
lifetime management via `moonbit_make_external_object`, then dogfooding in a
real DSP pipeline. 144 tests passing on native, 88 on wasm-gc. Module:
`dowdiness/arena` (Apache-2.0).

Implemented: `BumpAllocator` trait (with byte methods), `GenStore` trait,
`MbBump`, `MbGenStore`, `CFFIBump` (native), `CGenStore` (native), `Ref`,
`Arena[B, G]` with typed read/write, generational stale-ref detection, O(1)
reset, `Storable` trait (Double, Int, AudioFrame), `TypedRef[T]`,
`F64Arena[B, G]`, `I32Arena[B, G]`, `AudioArena[B, G]`, `AudioFrame`,
`BufferRef`, `AudioBufferPool[B, G]`, comprehensive input validation, FFI
safety guards, strict typed-arena contract enforcement (abort on post-alloc
write failure), allocator conformance tests, and benchmark suite (12 benchmarks
on wasm-gc, 24 on native).

---

## Phase 1 — Minimal Viable Arena (Pure MoonBit, all backends)

**Goal:** A working Arena with generational indices using only MoonBit constructs.
No C-FFI, no trait abstraction for backend switching. Keep everything in the root
package to start; restructure into sub-packages in Phase 2 when the second backend
is introduced.

### 1.1 MbBump — Bump allocator backed by FixedArray[Byte]

Implements the bump-pointer allocation semantics from §4.

```
struct MbBump {
    data : FixedArray[Byte]
    mut offset : Int
}
```

Functions:
- `MbBump::new(capacity: Int) -> MbBump`
- `MbBump::alloc(self, size: Int, align: Int) -> Int?` — returns byte offset or None
- `MbBump::reset(self) -> Unit` — sets offset to 0
- `MbBump::capacity(self) -> Int`
- `MbBump::used(self) -> Int`
- Bounds-checked typed read/write helpers:
  - `MbBump::write_int32(self, offset: Int, val: Int) -> Bool`
  - `MbBump::read_int32(self, offset: Int) -> Int?`
  - `MbBump::write_double(self, offset: Int, val: Double) -> Bool`
  - `MbBump::read_double(self, offset: Int) -> Double?`

Alignment: `alloc` rounds offset up to the next multiple of `align`.

Tests:
- Alloc returns sequential offsets with correct alignment
- Alloc returns None when capacity exhausted
- Reset brings used() back to 0
- Alloc works again after reset
- Read/write round-trip for Int and Double

### 1.2 MbGenStore — Generation storage backed by Array[Int]

Implements per-slot generation tracking from §5.3.

```
struct MbGenStore {
    data : Array[Int]
}
```

Functions:
- `MbGenStore::new(slot_count: Int) -> MbGenStore` — initialized to 0
- `MbGenStore::get(self, index: Int) -> Int`
- `MbGenStore::set(self, index: Int, generation: Int) -> Unit`
- `MbGenStore::length(self) -> Int`

Note: `invalidate_all` is not needed with lazy invalidation (§5.5).

Tests:
- get/set round-trip
- Initial values are 0
- Independent slot updates

### 1.3 Ref — Generational index

```
struct Ref {
    index : Int
    generation : Int
}
```

- Derive `Eq` and `Show`
- No public constructor; only `Arena::alloc` produces `Ref` values

### 1.4 Arena — Slot-based allocator with generation tracking

Core type from §5.4, using MbBump and MbGenStore directly (no enum dispatch yet).

```
struct Arena {
    bump : MbBump
    gen_store : MbGenStore
    mut generation : Int
    mut count : Int
    slot_size : Int
    max_slots : Int
}
```

Functions:
- `Arena::new(slot_count: Int, slot_size: Int) -> Arena`
- `Arena::alloc(self) -> Ref?` — allocates one slot, returns Ref with current generation
- `Arena::is_valid(self, ref: Ref) -> Bool` — validity predicate (§5.2)
- `Arena::slot_offset(self, ref: Ref) -> Int?` — byte offset for valid ref, None if stale
- `Arena::reset(self) -> Unit` — O(1) lazy invalidation (§5.5)
- `Arena::get_generation(self) -> Int` — current generation
- `Arena::get_count(self) -> Int` — allocated slot count
- `Arena::get_max_slots(self) -> Int` — max_slots

Typed access (validates ref and bounds-checks field_offset):
- `Arena::write_int32(self, ref: Ref, field_offset: Int, val: Int) -> Bool`
- `Arena::read_int32(self, ref: Ref, field_offset: Int) -> Int?`
- `Arena::write_double(self, ref: Ref, field_offset: Int, val: Double) -> Bool`
- `Arena::read_double(self, ref: Ref, field_offset: Int) -> Double?`

Tests:
- Alloc returns valid Refs
- is_valid returns true for fresh Refs
- is_valid returns false after reset (stale ref detection)
- Multiple alloc/reset cycles
- Alloc returns None at capacity
- slot_offset returns correct byte position
- Read/write round-trip through Arena
- Stale ref write returns false
- Stale ref read returns None

### 1.5 Safety hardening (implemented)

The Phase 1 implementation includes defensive checks beyond the original design:

- **Overflow-safe alignment**: uses modulo-based padding instead of `(offset + align - 1) / align * align`
- **Overflow-safe bounds checks**: `size > remaining` instead of `aligned + size > capacity`
- **Input validation**: rejects non-positive size/align in `MbBump::alloc`, negative capacity in constructors
- **Constructor overflow detection**: `Arena::new` detects `slot_count * slot_size` overflow, degrades to zero-capacity
- **Field offset bounds**: Arena typed accessors reject offsets outside the slot (overflow-safe)
- **Negative index guard**: `Arena::is_valid` rejects negative `Ref.index`
- **Bump alloc failure propagation**: `Arena::alloc` checks `MbBump::alloc` result before committing
- **Generation exhaustion**: `Arena::reset` aborts at `@int.max_value` rather than wrapping
- **Bounds-checked typed accessors**: `MbBump` read/write return `Bool`/`Option` instead of panicking

### 1.6 Cleanup (done)

- Removed placeholder `fib` and `sum` from `arena.mbt`
- Removed their tests from `arena_test.mbt`
- Moved MbBump, MbGenStore, Ref, Arena code into separate `.mbt` files in root package
- Ran `moon info && moon fmt`

### File layout (Phase 1)

```
arena/
├── mb_bump.mbt           # MbBump struct and methods
├── mb_bump_test.mbt      # MbBump tests
├── mb_gen_store.mbt      # MbGenStore struct and methods
├── mb_gen_store_test.mbt # MbGenStore tests
├── ref.mbt               # Ref struct
├── arena.mbt             # Arena struct and methods
├── arena_test.mbt        # Arena blackbox tests
├── arena_wbtest.mbt      # Arena whitebox tests (internal invariants)
├── moon.pkg.json
└── cmd/main/
    ├── main.mbt          # Arena usage demo
    └── moon.pkg.json
```

Note: Phase 1 file layout has been superseded by Phase 2 layout (see below).

---

## Phase 2 — Backend Abstraction & C-FFI (implemented)

**Goal:** Introduce trait-based abstraction and C-FFI backend.

**Design decision:** Uses generic type parameters with monomorphization instead of
enum dispatch. MoonBit monomorphizes trait-constrained generics, so
`Arena[MbBump, MbGenStore]` and `Arena[CFFIBump, CGenStore]` compile to fully
specialized functions with zero dispatch overhead. This is superior to the
originally planned enum dispatch approach.

### 2a — Traits & Generic Arena (implemented)

- Traits stay in root package (no sub-package restructuring needed)
- `BumpAllocator` trait (`bump_allocator.mbt`): alloc, reset, capacity, used, write_int32, read_int32, write_double, read_double, write_byte, read_byte
- `GenStore` trait (`gen_store_trait.mbt`): get, set, length
- `MbBump` implements `BumpAllocator` via trait impl blocks
- `MbGenStore` implements `GenStore` via trait impl blocks
- `Arena[B, G]` generic struct with trait-constrained methods
- `Arena::new_with[B, G]` generic constructor (validates bump is empty, clamps max_slots)
- `Arena::new` backward-compatible convenience constructor (returns `Arena[MbBump, MbGenStore]`)

### 2b — C-FFI Backend (implemented)

Native-only `cffi/` sub-package using `targets` conditional compilation in moon.pkg.json.

- `c_bump.c` / `c_bump.mbt` — `CFFIBump` struct with `BumpPtr`, implements `BumpAllocator`
- `c_gen.c` / `c_gen.mbt` — `CGenStore` struct with `GenPtr`, implements `GenStore`
- `cffi.mbt` — `new_arena()` convenience constructor returning `Arena[CFFIBump, CGenStore]`
- Safety: null-pointer abort on allocation failure, `destroyed` flag prevents use-after-free/double-free, bounds-checked indices before FFI boundary
- `destroy()` methods for explicit deterministic native memory cleanup

**Lifetime management (planned: hybrid approach with `moonbit_make_external_object`):**

Currently `BumpPtr`/`GenPtr` use `#external` (no RC, manual `destroy()` required).
The planned hybrid approach uses `moonbit_make_external_object` for automatic
finalization while keeping `destroy()` for deterministic early release:

- `BumpPtr`/`GenPtr` change from `#external type` to plain abstract `type` (RC-managed)
- C `bump_create`/`gen_create` use `moonbit_make_external_object` with finalize callbacks
- Finalizers free inner data buffers (`base`/`data`); the runtime frees the object itself
- `destroy()` becomes optional early release — sets buffer pointer to NULL
- Finalizers check for NULL to prevent double-free
- All hot-path operations use `#borrow(ptr)` — zero RC overhead on data path
- RC overhead limited to handle creation/destruction (typically once at startup/shutdown)

### File layout (Phase 2)

```
arena/
├── arena.mbt              # Arena[B, G] generic struct and methods
├── arena_test.mbt         # Arena blackbox tests
├── arena_wbtest.mbt       # Arena whitebox tests
├── bench_bump_test.mbt    # MbBump benchmarks
├── bench_gen_store_test.mbt # MbGenStore benchmarks
├── bench_arena_test.mbt   # Arena[MbBump,MbGenStore] benchmarks
├── bump_allocator.mbt     # BumpAllocator trait
├── gen_store_trait.mbt    # GenStore trait
├── mb_bump.mbt            # MbBump + BumpAllocator impl
├── mb_bump_test.mbt       # MbBump tests
├── mb_gen_store.mbt       # MbGenStore + GenStore impl
├── mb_gen_store_test.mbt  # MbGenStore tests
├── ref.mbt                # Ref struct (unchanged)
├── moon.pkg.json
├── cffi/                  # Native-only C-FFI backend
│   ├── c_bump.c           # C bump allocator
│   ├── c_bump.mbt         # CFFIBump wrapper + BumpAllocator impl
│   ├── c_bump_test.mbt    # CFFIBump tests
│   ├── c_gen.c            # C generation array
│   ├── c_gen.mbt          # CGenStore wrapper + GenStore impl
│   ├── c_gen_test.mbt     # CGenStore tests
│   ├── cffi.mbt           # new_arena() convenience constructor
│   ├── cffi_test.mbt      # Arena[CFFIBump, CGenStore] integration tests
│   ├── bench_bump_test.mbt      # CFFIBump benchmarks
│   ├── bench_gen_store_test.mbt # CGenStore benchmarks
│   ├── bench_arena_test.mbt     # Arena[CFFIBump,CGenStore] benchmarks
│   └── moon.pkg.json      # native-only, targets conditional compilation
└── cmd/main/
    ├── main.mbt
    └── moon.pkg.json
```

Note: Phase 2 file layout has been superseded by Phase 3 additions (see below).

### 2.x Benchmarks (implemented)

Benchmarks use MoonBit's built-in `moon bench` with `@bench.T`. Run with:

```bash
moon bench                    # MbBump benchmarks (wasm-gc)
moon bench --target native    # All benchmarks including CFFIBump
```

**Results (native target, 1000 ops/iteration):**

| Benchmark | MbBump | CFFIBump |
|-----------|--------|----------|
| alloc (8B, align=1) | ~7 µs | ~8 µs |
| alloc (8B, align=8) | ~7 µs | ~10 µs |
| int32 read/write | ~12 µs | ~10 µs |
| double read/write | ~15 µs | ~10 µs |

| Benchmark | MbGenStore | CGenStore |
|-----------|-----------|----------|
| get (1000 lookups) | ~8 µs | ~9 µs |
| set (1000 writes) | ~3 µs | ~2 µs |

| Benchmark | MbBump backend | CFFIBump backend |
|-----------|---------------|-----------------|
| Arena alloc 1000 slots | ~12 µs | ~12 µs |
| Arena write+read double | ~30 µs | ~25 µs |

Reset benchmarks:
- `reset baseline (empty arena)` measures empty-arena `reset()` only (near 0 µs).
- `reset+refill cycle (100 allocs)` and `(10000 allocs)` measure `reset(); alloc*N` in each iteration to keep a consistent non-empty-state scenario.
- Cycle timing scales with `N` because setup allocations are included intentionally.
- `reset-only complexity sweep (monotonic clock)` measures only `reset()` for `N=0/100/1000/10000`, with refill outside the timed window.

**Zero dispatch overhead confirmed:** Arena alloc cycle timing is virtually identical between `Arena[MbBump, MbGenStore]` (~12 µs) and `Arena[CFFIBump, CGenStore]` (~12 µs), confirming that monomorphization eliminates dispatch overhead.

Benchmark files:

```
arena/
├── bench_bump_test.mbt           # MbBump allocation + typed read/write throughput
├── bench_gen_store_test.mbt      # MbGenStore get/set throughput
├── bench_arena_test.mbt          # Arena[MbBump,MbGenStore] alloc, reset baseline, reset+refill cycle, read/write
├── cffi/
│   ├── bench_bump_test.mbt       # CFFIBump allocation + typed read/write throughput
│   ├── bench_gen_store_test.mbt  # CGenStore get/set throughput
│   └── bench_arena_test.mbt      # Arena[CFFIBump,CGenStore] alloc, reset baseline, reset+refill cycle, read/write
```

---

## Phase 3 — Typed Arena (implemented)

**Goal:** Type-safe serialization layer on top of Arena.

**Design decisions:**
- `Storable` trait uses byte-array based serialization (`FixedArray[Byte]`) instead
  of generic `BumpAllocator`-parameterized methods (MoonBit doesn't support generic
  type parameters on trait methods). Storable serves as a formalization and
  user-extensibility point.
- Specialized arenas (`F64Arena`, `I32Arena`, `AudioArena`) bypass `Storable` and
  use Arena's typed accessors (`write_double`, `read_double`, `write_int32`,
  `read_int32`) directly for zero-copy performance.
- `TypedRef[T]` uses `inner` field name (not `ref`) because `ref` is a reserved
  keyword in MoonBit.

### 3.1 Storable trait (implemented)

```
trait Storable {
    byte_size() -> Int
    write_bytes(Self, FixedArray[Byte], offset: Int) -> Unit
    read_bytes(FixedArray[Byte], offset: Int) -> Self
}
```

Built-in implementations: `Double` (8 bytes, LE), `Int` (4 bytes, LE), `AudioFrame` (16 bytes).

### 3.2 TypedRef[T] (implemented)

Phantom-typed wrapper around `Ref`. `T` is unused at runtime (phantom type) —
zero cost. Derives `Eq` and `Show`.

```
struct TypedRef[T] { inner : Ref }
```

### 3.3 Manual specialization — Pattern A (implemented)

All three arenas are generic: `F64Arena[B, G]`, `I32Arena[B, G]`, `AudioArena[B, G]`.
Each provides:
- `::new(slot_count)` — convenience constructor (MbBump backend)
- `::new_with(bump, gen_store, max_slots)` — generic constructor (any backend)
- `::alloc(self, value) -> TypedRef[T]?` — allocate and write initial value
  (aborts on post-alloc write failure: `BumpAllocator` contract violation)
- `::get(self, tref) -> T?` — read value (None if stale)
- `::set(self, tref, value) -> Bool` — overwrite value (false if stale)
- `::reset(self)` — delegates to arena.reset()
- `::is_valid(self, tref) -> Bool` — delegates to arena.is_valid()

| Arena | Type | Slot size | Accessors used |
|-------|------|-----------|----------------|
| `F64Arena` | `Double` | 8 | `write_double`/`read_double` |
| `I32Arena` | `Int` | 4 | `write_int32`/`read_int32` |
| `AudioArena` | `AudioFrame` | 16 | `write_double` x2 / `read_double` x2 |

### 3.4 AudioFrame (implemented)

```
struct AudioFrame { left : Double, right : Double }
```

Constructor: `AudioFrame::new(left, right)`. Storable impl writes left at offset 0,
right at offset 8.

### 3.5 Tests (implemented)

- Storable round-trip: Double, Int, AudioFrame (storable_test.mbt — 6 tests)
- TypedRef Eq/Show (typed_ref_wbtest.mbt — 4 tests)
- F64Arena: alloc, get, set, stale ref, capacity, multiple cycles (f64_arena_test.mbt — 6 tests)
- I32Arena: same pattern (i32_arena_test.mbt — 6 tests)
- AudioArena: same pattern + left/right independence (audio_arena_test.mbt — 7 tests)
- Typed arena contract violation behavior (typed_arena_alloc_failure_test.mbt — 3 panic tests)
- BumpAllocator conformance tests for MbBump (bump_allocator_conformance_test.mbt — 3 tests)
- CFFIBump backend: F64Arena, I32Arena, AudioArena (cffi/typed_arena_test.mbt — 11 tests)
- CFFIBump conformance tests (cffi/bump_allocator_conformance_test.mbt — 3 tests)

Total: 71 tests wasm-gc, 119 tests native.

### File layout (Phase 3 additions)

```
arena/
├── storable.mbt             # Storable trait + Double/Int impls
├── storable_test.mbt        # Storable round-trip tests
├── typed_ref.mbt            # TypedRef[T] phantom-typed wrapper
├── typed_ref_wbtest.mbt     # TypedRef Eq/Show whitebox tests
├── audio_frame.mbt          # AudioFrame struct + Storable impl
├── f64_arena.mbt            # F64Arena[B, G]
├── f64_arena_test.mbt       # F64Arena tests
├── i32_arena.mbt            # I32Arena[B, G]
├── i32_arena_test.mbt       # I32Arena tests
├── audio_arena.mbt          # AudioArena[B, G]
├── audio_arena_test.mbt     # AudioArena tests
├── typed_arena_alloc_failure_test.mbt  # Contract-violation panic tests
├── bump_allocator_conformance_test.mbt # MbBump contract tests
├── cffi/
│   ├── typed_arena_test.mbt # Typed arena tests with CFFIBump/CGenStore
│   └── bump_allocator_conformance_test.mbt # CFFIBump contract tests
```

---

## Phase 4 — DSP Domain Integration

**Goal:** Audio/DSP-specific wrappers. Dogfood the library in a real DSP pipeline.
Other domain integrations (ASTArena, incr, CRDT) are deferred to future improvements.

### 4.1 AudioBufferPool (§8.1) — implemented

`AudioBufferPool[B, G]` wraps `Arena[B, G]` with DSP-specific semantics:
multi-sample buffers indexed by frame and channel, with `BufferRef` references.

**BumpAllocator byte methods (prep for 4.2):**
- Added `write_byte(Self, Int, Byte) -> Bool` and `read_byte(Self, Int) -> Byte?` to `BumpAllocator` trait
- Implemented for `MbBump` (bounds-checked byte array access) and `CFFIBump` (with C stubs `bump_write_byte`/`bump_read_byte`)

**BufferRef:**
- Newtype wrapping `Ref` (not `TypedRef[T]` — audio buffers are multi-sample containers, not single typed values)
- Derives `Eq` and `Show`

**AudioBufferPool[B, G]:**

```
struct AudioBufferPool[B, G] {
  arena             : Arena[B, G]
  frames_per_buffer : Int
  channels          : Int
}
```

Key design decisions:
- **Interleaved sample layout**: `field_offset = (frame * channels + channel) * 8`. Each sample is a `Double` (8 bytes)
- **alloc() returns `BufferRef?`** with no initial value — unlike typed arenas that initialize on alloc. Audio buffers are large and will be written by DSP processing
- **Sample access**: `write_sample(bref, frame, channel, value) -> Bool` and `read_sample(bref, frame, channel) -> Double?` with bounds checking on frame and channel indices
- **Constructor overflow safety**: detects `frames_per_buffer * channels * 8` overflow, degrades to zero-capacity

Methods:
- `AudioBufferPool::new(frames_per_buffer, channels, buffer_count)` — MbBump convenience constructor
- `AudioBufferPool::new_with(bump, gen_store, frames_per_buffer, channels, max_buffers)` — generic constructor
- `AudioBufferPool::alloc(self) -> BufferRef?`
- `AudioBufferPool::write_sample(self, bref, frame, channel, value) -> Bool`
- `AudioBufferPool::read_sample(self, bref, frame, channel) -> Double?`
- `AudioBufferPool::reset(self)` / `is_valid(self, bref)` / `get_frames_per_buffer(self)` / `get_channels(self)`

Tests (17 new wasm-gc + 25 new native):
- BufferRef Eq/Show whitebox tests (3)
- AudioBufferPool blackbox tests with MbBump: alloc, stereo/mono round-trip, OOB frame/channel, stale ref, capacity, multi-cycle, multi-buffer independence, per-callback lifecycle, getters, overflow constructor (12)
- AudioBufferPool cffi tests with CFFIBump/CGenStore (5)
- MbBump byte read/write round-trip + bounds tests (2)
- CFFIBump byte read/write round-trip + bounds + destroy safety tests (3)

Total: 88 tests wasm-gc, 144 tests native.

### File layout (Phase 4.1 additions)

```
arena/
├── buffer_ref.mbt                  # BufferRef struct wrapping Ref
├── buffer_ref_wbtest.mbt           # BufferRef Eq/Show whitebox tests
├── audio_buffer_pool.mbt           # AudioBufferPool[B, G]
├── audio_buffer_pool_test.mbt      # AudioBufferPool blackbox tests (MbBump)
├── cffi/
│   └── audio_buffer_pool_test.mbt  # AudioBufferPool tests (CFFIBump/CGenStore)
```

Modified files:
- `bump_allocator.mbt` — added `write_byte`, `read_byte` to trait
- `mb_bump.mbt` — byte method implementations
- `cffi/c_bump.c` — C stubs for byte read/write
- `cffi/c_bump.mbt` — CFFIBump byte method implementations
- `mb_bump_test.mbt` — byte method tests
- `cffi/c_bump_test.mbt` — CFFIBump byte method + destroy safety tests

---

## Phase 5 — Hybrid C-FFI Lifetime Management

**Goal:** Replace manual `destroy()` requirement with automatic finalization via
`moonbit_make_external_object`, while keeping `destroy()` for deterministic early
release. See `memory-management-design.md` §5.3 for full design rationale.

### 5.1 CFFIBump finalization

- Refactor `bump_create` to use `moonbit_make_external_object(bump_finalize, sizeof(BumpArena))`
- Add `bump_finalize(void* self)` — frees `base` only, sets `base = NULL`
- Update `bump_destroy` — frees `base`, sets `base = NULL` (no `free(a)` — runtime frees the object)
- Change `BumpPtr` from `#external type` to plain `type` (RC-managed)
- Remove `bump_is_null` (replaced by `moonbit_make_external_object` failure handling)

### 5.2 CGenStore finalization

- Same pattern for `gen_create`/`gen_finalize`/`gen_destroy`
- Change `GenPtr` from `#external type` to plain `type` (RC-managed)
- Remove `gen_is_null`

### 5.3 Safety invariants

- `destroyed` flag remains: guards use-after-destroy and double-free
- Finalizer checks `base == NULL` / `data == NULL` to skip if already destroyed
- All hot-path operations keep `#borrow(ptr)` — zero RC overhead on data path

### 5.4 Tests

- Verify automatic cleanup (arena goes out of scope without explicit destroy)
- Verify explicit destroy + finalizer interaction (no double-free)
- Verify hot-path operations still use `#borrow` (no RC overhead)
- Update all existing CFFIBump/CGenStore tests for new behavior

---

## Future Improvements

Low priority. Implement as needed. The library will be dogfooded in a real DSP
pipeline first. Other domain integrations are deferred until the core API is
validated through production DSP use.

### Audio / DSP Extensions

- **get_unchecked / set_unchecked**: Level 0 unsafe access for profiled DSP hot paths
- **Memory statistics**: usage tracking and visualization for buffer pools

### Other Domain Integrations (deferred)

These were originally planned as Phase 4.2–4.3 but are deferred until the
library is proven in DSP use cases. The core Arena API and `write_byte`/`read_byte`
(already implemented) provide the foundation when these are needed.

- **ASTArena** (§8.2): dual-arena (node_arena + string_arena), StringRef, parse/convert/reset lifecycle. Uses `write_byte`/`read_byte` for string storage.
- **incr generation synchronization**: mechanism to tie MemoTable generation to Arena generation
- **CRDTOpPool** (§8.3): batch operation pool

### Infrastructure

- **GrowableArena** (§10): chunk-chained arena for unknown-size inputs
- **Code generation**: auto-generate Pattern A TypedArena specializations

---

## Decision Log

| Decision | Chosen | Rationale |
|----------|--------|-----------|
| Phase 1 package structure | Flat (root package) | Simplest start; refactor when second backend requires it |
| Phase 1 backend | MbBump only (no traits) | No abstraction needed without a second implementation |
| invalidate_all on reset | Lazy (§5.5) | O(1) reset is critical for DSP |
| Generation overflow | Abort at max_value | Wrapping reuses generation values, breaking stale-ref safety; 2^31 resets is unreachable in practice |
| Typed accessor return types | Bool/Option (not Unit/bare) | Public API must not panic on bad offsets; recoverable failure via return values |
| Alignment arithmetic | Modulo-based padding | `(offset + align - 1) / align * align` overflows for large align values |
| TypedArena pattern | Pattern A (manual specialization) | Simple, optimizable; boilerplate acceptable for 2-3 types |
| Phase 2 dispatch mechanism | Generic type params (not enum dispatch) | MoonBit monomorphizes generics — zero dispatch overhead, no runtime cost vs enum match |
| Phase 2 package structure | Traits in root, C-FFI in `cffi/` sub-package | No restructuring needed; `targets` conditional compilation isolates native-only code |
| C-FFI safety | Abort on null + destroyed flag + bounds checks | Fail fast on allocation failure; prevent use-after-free, double-free, and OOB writes before crossing FFI boundary |
| C-FFI lifetime (planned) | Hybrid: `moonbit_make_external_object` + `destroy()` | Automatic finalization prevents leaks; explicit `destroy()` for deterministic cleanup in DSP reconfiguration; `#borrow` on all ops means zero RC overhead on hot path |
| new_with preconditions | Abort on non-empty bump, clamp max_slots | Prevents silent invariant violations (wrong slot offsets, OOB gen_store access) |
| Typed alloc write failure | Abort (contract violation) | Successful `alloc` must guarantee writable initialized slots; avoid silent slot leaks |
| Storable trait signature | Byte-array based (`FixedArray[Byte]`) | MoonBit doesn't support generic type params on trait methods; byte-array is the viable design |
| Specialized arenas bypass Storable | Direct typed accessors | Zero-copy; avoids unnecessary byte-array intermediaries for built-in types |
| TypedRef field name | `inner` (not `ref`) | `ref` is a reserved keyword in MoonBit |
| AudioFrame slot layout | left at offset 0, right at offset 8 | Natural field order, two contiguous Doubles |
| BufferRef type | Newtype over `Ref` (not `TypedRef[T]`) | Audio buffers are multi-sample containers, not single typed values |
| AudioBufferPool alloc | No initial value written | Buffers are large; DSP will overwrite all samples anyway |
| AudioBufferPool alloc failure | Returns `None` (no abort) | No post-alloc write to fail, unlike typed arenas |
| Sample layout | Interleaved: `(frame * channels + channel) * 8` | Natural for per-frame DSP processing |
| BumpAllocator byte methods | Added `write_byte`/`read_byte` to trait | Prepares for ASTArena string storage (Phase 4.2) |

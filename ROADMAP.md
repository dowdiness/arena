# Implementation Roadmap

Based on the design in `memory-management-design.md` (§12).

## Current State

**Phase 3 is complete.** Type-safe wrappers are now implemented on top of the
generic arena. The `Storable` trait provides byte-array serialization for
user-defined types. `TypedRef[T]` adds phantom-typed references with zero
runtime cost. Three manually specialized arenas (`F64Arena`, `I32Arena`,
`AudioArena`) provide type-safe alloc/get/set using Arena's typed accessors
directly (no byte-array intermediary). 119 tests passing on native, 71 on
wasm-gc. Module: `dowdiness/arena` (Apache-2.0).

Implemented: `BumpAllocator` trait, `GenStore` trait, `MbBump`, `MbGenStore`,
`CFFIBump` (native), `CGenStore` (native), `Ref`, `Arena[B, G]` with typed
read/write, generational stale-ref detection, O(1) reset, `Storable` trait
(Double, Int, AudioFrame), `TypedRef[T]`, `F64Arena[B, G]`, `I32Arena[B, G]`,
`AudioArena[B, G]`, `AudioFrame`, comprehensive input validation, FFI safety
guards, strict typed-arena contract enforcement (abort on post-alloc write
failure), allocator conformance tests, and benchmark suite (12 benchmarks on
wasm-gc, 24 on native).

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
- `BumpAllocator` trait (`bump_allocator.mbt`): alloc, reset, capacity, used, write_int32, read_int32, write_double, read_double
- `GenStore` trait (`gen_store_trait.mbt`): get, set, length
- `MbBump` implements `BumpAllocator` via trait impl blocks
- `MbGenStore` implements `GenStore` via trait impl blocks
- `Arena[B, G]` generic struct with trait-constrained methods
- `Arena::new_with[B, G]` generic constructor (validates bump is empty, clamps max_slots)
- `Arena::new` backward-compatible convenience constructor (returns `Arena[MbBump, MbGenStore]`)

### 2b — C-FFI Backend (implemented)

Native-only `cffi/` sub-package using `targets` conditional compilation in moon.pkg.json.

- `c_bump.c` / `c_bump.mbt` — `CFFIBump` struct with opaque `BumpPtr`, implements `BumpAllocator`
- `c_gen.c` / `c_gen.mbt` — `CGenStore` struct with opaque `GenPtr`, implements `GenStore`
- `cffi.mbt` — `new_arena()` convenience constructor returning `Arena[CFFIBump, CGenStore]`
- Safety: null-pointer abort on allocation failure, `destroyed` flag prevents use-after-free/double-free, bounds-checked indices before FFI boundary
- Manual `destroy()` methods for explicit native memory cleanup

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

## Phase 4 — Domain Integration

**Goal:** Domain-specific wrappers for real use cases.

### 4.1 AudioBufferPool (§8.1)

- Struct wrapping Arena with frames_per_buffer and channels config
- Per-callback lifecycle: reset → alloc → process → return
- Integration test simulating audio callback pattern

### 4.2 ASTArena (§8.2)

- Dual-arena (node_arena + string_arena)
- StringRef for variable-length data
- Phase lifecycle: parse → convert → reset

### 4.3 incr generation synchronization

- Mechanism to tie MemoTable generation to Arena generation

---

## Phase 5 — Extensions

Low priority. Implement as needed.

- **GrowableArena** (§10): chunk-chained arena for unknown-size inputs
- **Code generation**: auto-generate Pattern A TypedArena specializations
- **Memory statistics**: usage tracking and visualization
- **get_unchecked**: Level 0 unsafe access for profiled hot paths

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
| new_with preconditions | Abort on non-empty bump, clamp max_slots | Prevents silent invariant violations (wrong slot offsets, OOB gen_store access) |
| Typed alloc write failure | Abort (contract violation) | Successful `alloc` must guarantee writable initialized slots; avoid silent slot leaks |
| Storable trait signature | Byte-array based (`FixedArray[Byte]`) | MoonBit doesn't support generic type params on trait methods; byte-array is the viable design |
| Specialized arenas bypass Storable | Direct typed accessors | Zero-copy; avoids unnecessary byte-array intermediaries for built-in types |
| TypedRef field name | `inner` (not `ref`) | `ref` is a reserved keyword in MoonBit |
| AudioFrame slot layout | left at offset 0, right at offset 8 | Natural field order, two contiguous Doubles |

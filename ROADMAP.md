# Implementation Roadmap

Based on the design in `memory-management-design.md` (§12).

## Current State

The codebase contains placeholder functions (`fib`, `sum`) in a flat root package.
No arena implementation exists yet. The module is `dowdiness/arena` (MoonBit, Apache-2.0).

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
- Byte-level read/write helpers:
  - `MbBump::write_byte(self, offset: Int, val: Byte) -> Unit`
  - `MbBump::read_byte(self, offset: Int) -> Byte`
  - `MbBump::write_int32(self, offset: Int, val: Int) -> Unit`
  - `MbBump::read_int32(self, offset: Int) -> Int`
  - `MbBump::write_double(self, offset: Int, val: Double) -> Unit`
  - `MbBump::read_double(self, offset: Int) -> Double`

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

Functions:
- `Ref::new(index: Int, generation: Int) -> Ref`
- Derive `Eq` and `Show`

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
- `Arena::generation(self) -> Int` — current generation
- `Arena::count(self) -> Int` — allocated slot count
- `Arena::capacity(self) -> Int` — max_slots

Raw byte access via slot_offset + MbBump read/write:
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

### 1.5 Cleanup

- Remove placeholder `fib` and `sum` from `arena.mbt`
- Remove their tests from `arena_test.mbt`
- Move MbBump, MbGenStore, Ref, Arena code into separate `.mbt` files in root package
- Run `moon info && moon fmt`

### Suggested file layout for Phase 1

```
arena/
├── mb_bump.mbt          # MbBump struct and methods
├── mb_bump_test.mbt     # MbBump tests
├── mb_gen_store.mbt     # MbGenStore struct and methods
├── mb_gen_store_test.mbt # MbGenStore tests
├── ref.mbt              # Ref struct
├── arena.mbt            # Arena struct and methods (replaces placeholder)
├── arena_test.mbt       # Arena tests (replaces placeholder)
├── moon.pkg.json
└── cmd/main/
    ├── main.mbt
    └── moon.pkg.json
```

---

## Phase 2 — Backend Abstraction & C-FFI

**Goal:** Introduce trait-based abstraction and C-FFI backend. Restructure into
sub-packages per §11.

### 2.1 Package restructuring

Split root package into:
- `bump/` — BumpAllocator trait, MbBump, CFFIBump
- `gen_store/` — GenStore trait, MbGenStore, CGenStore
- `core/` — Ref, Arena, BumpImpl/GenStoreImpl enums

### 2.2 BumpAllocator trait

Extract the common interface from MbBump into a trait (§4.2).

### 2.3 GenStore trait

Extract the common interface from MbGenStore into a trait (§5.3).

### 2.4 CFFIBump (native only)

- Write `c_bump.c` with the C interface from §4.3
- Write `CFFIBump` MoonBit wrapper with FFI extern declarations
- Add finalizer to call `bump_destroy`

### 2.5 CGenStore (native only)

- Write `c_gen.c` with C int array
- Write `CGenStore` MoonBit wrapper with FFI extern declarations
- Add finalizer

### 2.6 Enum dispatch

```
enum BumpImpl { Mb(MbBump) | C(CFFIBump) }
enum GenStoreImpl { Mb(MbGenStore) | C(CGenStore) }
```

### 2.7 Configuration constructors

- `Arena::new_debug` — MbBump + MbGenStore
- `Arena::new_release` — CFFIBump + CGenStore
- `Arena::new_hybrid` — CFFIBump + MbGenStore

### 2.8 Benchmarks

- MbBump vs CFFIBump allocation throughput
- MbGenStore vs CGenStore lookup throughput
- Arena alloc/reset cycle timing

---

## Phase 3 — Typed Arena

**Goal:** Type-safe serialization layer on top of Arena.

### 3.1 Storable trait (§6.2)

```
trait Storable {
    byte_size() -> Int
    write_to(Self, bump: BumpImpl, offset: Int) -> Unit
    read_from(bump: BumpImpl, offset: Int) -> Self
}
```

### 3.2 Built-in Storable implementations

- `Double` (8 bytes)
- `Int` (4 bytes)

### 3.3 TypedRef[T] (§6.3)

Phantom-typed wrapper around Ref.

### 3.4 Manual specialization (Pattern A from §6.4)

- `F64Arena` — TypedArena for Double
- `I32Arena` — TypedArena for Int

### 3.5 Domain type: AudioFrame

```
struct AudioFrame { left: Double, right: Double }  // 16 bytes
```

- Storable implementation
- `AudioArena` specialization

### 3.6 Tests

- Type safety: TypedRef[Double] cannot be used with AudioArena
- Round-trip serialization for all Storable types
- Stale TypedRef detection

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
| invalidate_all on reset | Lazy (§5.5) | O(1) reset is critical for DSP; no practical generation overflow risk |
| TypedArena pattern | Pattern A (manual specialization) | Simple, optimizable; boilerplate acceptable for 2-3 types |

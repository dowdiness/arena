# MoonBit Memory Management Library — Design Document

> Target audience: Claude Code and human developers.
> Each section is self-contained. Cross-references use `§N` notation.

---

## §1 Problem Statement

MoonBit ships with Perceus (reference-counting) GC. It works well for general
application code but falls short in four specific domains:

| Domain | Problem with GC |
|--------|----------------|
| Real-time DSP | RC increments/decrements on every sample are unacceptable; any GC pause breaks audio |
| Parser | Mass-allocating temporary AST nodes incurs per-node RC overhead |
| CRDT | Batch-applying remote operations creates short-lived intermediate objects |
| Incremental computation (incr) | Memo tables need generation-based bulk invalidation |

**Goal**: Provide a layered Arena allocator library that lets each domain opt
into manual memory management only where needed, while keeping the rest of the
codebase under normal GC.

---

## §2 Design Principles

1. **Incremental adoption** — GC-managed code requires zero changes.
2. **Separation of concerns** — Physical memory (C) vs. logical lifetime (MoonBit).
3. **Backend-switchable** — Pure MoonBit (all backends) or C-FFI (native only).
4. **Domain-agnostic core** — DSP, parser, CRDT, and incr all build on the same primitives.

---

## §3 Architecture Overview

```
╔═══════════════════════════════════════════════════════════════╗
║                     Domain Layer                              ║
║  AudioBufferPool   ASTArena   CRDTOpPool   MemoTable          ║
╠═══════════════════════════════════════════════════════════════╣
║                     Layer 3 — Typed Arena                     ║
║  TypedArena[T]     TypedRef[T]     Storable (trait)           ║
╠═══════════════════════════════════════════════════════════════╣
║                     Layer 2 — Generic Arena                   ║
║  Arena             Ref             GenStore (trait)            ║
╠═══════════════════════════════════════════════════════════════╣
║                     Layer 1 — Physical Memory                 ║
║  BumpAllocator (trait)                                        ║
║    ├─ CFFIBump   (C malloc/mmap, GC-free, native only)       ║
║    └─ MbBump     (FixedArray[Byte], all backends)             ║
╚═══════════════════════════════════════════════════════════════╝
```

Data flows downward: Domain → L3 → L2 → L1.
Safety checks flow upward: L1 (bounds) → L2 (generation) → L3 (type).

---

## §4 Layer 1 — Physical Memory

### §4.1 Semantics

Layer 1 manages a contiguous byte buffer via bump-pointer allocation.
It has no concept of types or slots. It only knows bytes and offsets.

**State machine:**

```
Created ──alloc()──▶ Allocated ──alloc()──▶ ... ──▶ Full
   ▲                     │                            │
   └──── reset() ────────┴──────── reset() ───────────┘
```

- `alloc()` always advances the offset (never retreats).
- `reset()` sets offset to 0. Memory is not freed; it is reused.
- After `reset()`, all previously returned offsets are logically invalid,
  but Layer 1 does **not** detect invalid access. That is Layer 2's job.

### §4.2 Trait: BumpAllocator

```
trait BumpAllocator {
    alloc(Self, size: Int, align: Int) -> Int?
    //  Returns byte offset on success, None on capacity exhaustion.
    //  Postcondition: returned offset is a multiple of `align`.

    reset(Self) -> Unit
    //  Resets offset to 0. O(1).
    //  Postcondition: used() == 0.

    capacity(Self) -> Int
    //  Total capacity in bytes. Constant after creation.

    used(Self) -> Int
    //  Bytes allocated since last reset.
}
```

### §4.3 Implementation A: CFFIBump (native only, GC-free)

Backed by `malloc`-allocated memory on the C side.
MoonBit holds an opaque pointer; a finalizer calls `free` on GC collection.

**C interface:**

```c
typedef struct { char* base; size_t offset; size_t capacity; } BumpArena;

BumpArena* bump_create(size_t capacity);
size_t     bump_alloc(BumpArena* a, size_t size, size_t align);
void       bump_reset(BumpArena* a);
void       bump_destroy(BumpArena* a);

// Typed read/write helpers (avoid per-byte FFI calls)
void   bump_write_f64(BumpArena* a, size_t offset, double val);
double bump_read_f64(BumpArena* a, size_t offset);
void   bump_write_i32(BumpArena* a, size_t offset, int32_t val);
int32_t bump_read_i32(BumpArena* a, size_t offset);
void   bump_memcpy(BumpArena* a, size_t dst, size_t src, size_t len);
```

**When to use:** DSP hot paths, any code path where GC pauses are unacceptable.

### §4.4 Implementation B: MbBump (all backends)

Backed by `FixedArray[Byte]` managed by MoonBit's GC.

```
struct MbBump {
    data : FixedArray[Byte]
    mut offset : Int
}
```

**When to use:** wasm-gc / JS backends, or native code where GC pauses are
tolerable (CRDT batch processing, non-real-time parsing).

---

## §5 Layer 2 — Generic Arena

### §5.1 Semantics

Layer 2 introduces **slots** (fixed-size regions within the bump buffer) and
**generational indices** that detect use-after-reset at runtime.

### §5.2 Type: Ref

```
struct Ref {
    index      : Int   // Slot number (0-based)
    generation : Int   // Arena generation at allocation time
}
```

**Validity predicate:**

```
valid(ref, arena) ⟺
    ref.index < arena.count
  ∧ ref.generation == arena.generation
  ∧ arena.gen_store.get(ref.index) == ref.generation
```

**Key properties:**
- Copy-type. No reference counting needed to pass around.
- After `arena.reset()`, `valid(ref, arena)` is false for ALL existing Refs.
- Two Refs are equal iff they point to the same slot in the same generation.

### §5.3 Trait: GenStore

Stores per-slot generation numbers. Abstracted to allow MoonBit/C switching.

```
trait GenStore {
    get(Self, index: Int) -> Int
    set(Self, index: Int, generation: Int) -> Unit
    length(Self) -> Int
    invalidate_all(Self, new_generation: Int) -> Unit
}
```

**Implementations:**

| Name | Backing storage | GC involvement | Target |
|------|----------------|----------------|--------|
| `MbGenStore` | `Array[Int]` | Yes (GC-managed) | All backends |
| `CGenStore` | C `int*` array | No | Native only |

### §5.4 Type: Arena

```
struct Arena {
    bump       : BumpImpl        // Physical memory (enum, see §7)
    gen_store  : GenStoreImpl    // Generation storage (enum, see §7)
    mut generation : Int         // Current arena-wide generation
    mut count  : Int             // Number of allocated slots
    slot_size  : Int             // Bytes per slot (fixed at creation)
    max_slots  : Int             // capacity / slot_size
}
```

**Operations:**

```
fn Arena::alloc(self) -> Ref?
    // Allocates one slot.
    // Returns None if count == max_slots.
    // Postcondition: valid(returned_ref, self) == true.

fn Arena::is_valid(self, ref: Ref) -> Bool
    // Checks the validity predicate (§5.2).

fn Arena::slot_offset(self, ref: Ref) -> Int?
    // Returns the byte offset for ref's slot, or None if stale.
    // offset = ref.index * self.slot_size

fn Arena::reset(self) -> Unit
    // Resets bump allocator, increments generation, sets count to 0.
    // Postcondition: for all previously returned Refs r, valid(r, self) == false.
```

### §5.5 Lazy Invalidation on Reset

A naive `reset()` writes -1 to every slot in `gen_store` — O(n).
With lazy invalidation, `reset()` is O(1):

```
fn reset(self) {
    self.bump.reset()
    self.generation += 1   // This alone logically invalidates all Refs.
    self.count = 0
    // gen_store is NOT touched.
}

fn alloc(self) -> Ref? {
    // Only writes the current generation to the NEW slot.
    self.gen_store.set(self.count, self.generation)
    ...
}

fn is_valid(self, ref) -> Bool {
    // Old gen_store entries are stale because ref.generation
    // won't match self.generation.
    ref.generation == self.generation
    && ref.index < self.count
    && self.gen_store.get(ref.index) == ref.generation
}
```

This makes `reset()` O(1) — critical for DSP block boundaries called ~172 times/sec.

### §5.6 Generation Overflow

At 172 resets/sec (44100 Hz / 256 frames), `Int` (2^31) overflows after ~395 years.
Not a practical concern. Defensive option: clear gen_store on overflow.

---

## §6 Layer 3 — Typed Arena

### §6.1 Semantics

Layer 3 attaches type information to Layer 2 slots, providing type-safe
serialization/deserialization of domain values to/from raw bytes.

### §6.2 Trait: Storable

```
trait Storable {
    byte_size() -> Int
    //  Fixed size in bytes. Same for all instances of a given type.

    write_to(Self, bump: BumpImpl, offset: Int) -> Unit
    //  Serialize self into bump buffer at the given offset.

    read_from(bump: BumpImpl, offset: Int) -> Self
    //  Deserialize a value from bump buffer at the given offset.
}
```

**Built-in implementations:**

| Type | byte_size | Read/Write via |
|------|-----------|---------------|
| `Double` | 8 | `bump_write_f64` / `bump_read_f64` |
| `Int` | 4 | `bump_write_i32` / `bump_read_i32` |
| `AudioFrame { left: Double, right: Double }` | 16 | Two f64 writes |

**Constraint:** Only fixed-size types can implement `Storable` directly.
Variable-length data (strings, arrays) is stored as an offset+length pair
pointing elsewhere in the arena. See §8.2 (ASTArena) for the pattern.

### §6.3 Type: TypedRef[T]

```
struct TypedRef[T] {
    ref : Ref
}
```

Phantom type parameter `T` prevents mixing references across arenas of
different types at compile time. Zero runtime cost — it is just a `Ref`.

### §6.4 TypedArena[T] and MoonBit's Trait Limitation

MoonBit does not support bounded type parameters on structs
(i.e., `struct TypedArena[T : Storable]` may not work). Three workarounds:

**Pattern A — Manual specialization (recommended to start):**

```
struct F64Arena     { arena : Arena }
struct AudioArena   { arena : Arena }

fn F64Arena::alloc(self, val: Double) -> TypedRef[Double]? { ... }
fn AudioArena::alloc(self, val: AudioFrame) -> TypedRef[AudioFrame]? { ... }
```

Pros: Simple, optimizable. Cons: Boilerplate per type.

**Pattern B — Closure-based erasure:**

```
struct TypedArena {
    arena    : Arena
    write_fn : (BumpImpl, Int, ???) -> Unit   // type-erased
    read_fn  : (BumpImpl, Int) -> ???
}
```

Pros: Single type. Cons: Loses type safety, closure overhead.

**Pattern C — Code generation (future):**

Auto-generate Pattern A via build script or macro once patterns stabilize.

**Recommendation:** Start with Pattern A for 2–3 domain types. Extract the
common pattern later.

---

## §7 Backend Switching

### §7.1 Enum Dispatch

```
enum BumpImpl {
    Mb(MbBump)
    C(CFFIBump)
}

enum GenStoreImpl {
    Mb(MbGenStore)
    C(CGenStore)
}
```

Arena uses these enums internally. All operations dispatch via `match`.

### §7.2 Configuration Constructors

```
fn Arena::new_debug(slot_count: Int, slot_size: Int) -> Arena
    // Uses MbBump + MbGenStore. Works on all backends.

fn Arena::new_release(slot_count: Int, slot_size: Int) -> Arena
    // Uses CFFIBump + CGenStore. Native only, GC-free.

fn Arena::new_hybrid(slot_count: Int, slot_size: Int) -> Arena
    // Uses CFFIBump + MbGenStore. GC-free memory, MoonBit-side checks.
```

### §7.3 Cost Analysis of Enum Dispatch

```
match branch:          ~1 ns  (branch-predicted)
C-FFI call overhead:   ~5-20 ns  (indirect function pointer)
bump_alloc itself:     ~2-5 ns  (pointer arithmetic)
f64 read/write:        ~1 ns

Conclusion: enum match cost is negligible compared to FFI overhead.
The real optimization target is reducing the NUMBER of FFI calls,
not eliminating match branches.
```

**Optimization pattern for DSP:**

```
// BAD: FFI call per sample
for frame in 0..<256 {
    arena.get_sample(ref, frame)  // FFI + match + bounds check each time
}

// GOOD: validate once, delegate loop to C
let offset = arena.slot_offset(ref).unwrap()
c_process_block(arena.bump_ptr(), offset, 256)  // single FFI call
```

### §7.4 Alternative: Package-Level Switching

Instead of enum dispatch, provide two packages with identical signatures:

```
arena_debug/    → uses MbBump + MbGenStore
arena_release/  → uses CFFIBump + CGenStore
```

Consumer code switches by changing the import. Zero runtime dispatch cost.
Trade-off: cannot mix backends within the same compilation unit.

---

## §8 Domain Layer — Usage Patterns

### §8.1 DSP: AudioBufferPool

**Purpose:** Allocate and reuse audio buffers within a single audio callback
without any GC involvement.

```
struct AudioBufferPool {
    arena             : Arena   // slot_size = frames_per_buffer * channels * 8
    frames_per_buffer : Int
    channels          : Int
}
```

**Lifecycle per audio callback:**

```
1. arena.reset()                         // O(1), invalidates all prior Refs
2. let temp = arena.alloc()              // O(1), bump pointer advance
3. DSP processing via C-side read/write  // zero GC, zero alloc
4. Callback returns                      // nothing to free
```

**Invariant:** Refs must NOT survive across callbacks.
`reset()` at the start of each callback enforces this — any stale Ref
from the previous callback will fail `is_valid()`.

**Persistent buffers** (delay lines, reverb tails): Use a separate Arena
that is NOT reset per callback, or use normal MoonBit arrays under GC.

### §8.2 Parser: ASTArena

**Purpose:** Mass-allocate AST nodes during a parse phase, then bulk-release.

```
struct ASTArena {
    node_arena   : Arena   // Fixed-size AST node records
    string_arena : Arena   // Variable-length identifier/literal strings
}
```

**AST node representation in the arena:**

```
// Example: BinaryExpr stored as a fixed-size record
//   op    : Int  (4 bytes) — enum tag for +, -, *, /
//   left  : Ref  (8 bytes) — index + generation
//   right : Ref  (8 bytes)
//   Total: 20 bytes per slot (padded to 24 for alignment)
```

**Variable-length data (strings):**

```
// Strings are written directly into string_arena.
// AST nodes hold a StringRef:
struct StringRef {
    offset : Int   // byte offset within string_arena
    length : Int   // byte length
}
// StringRef is 8 bytes — fits inside a fixed-size node slot.
```

**Phase lifecycle:**

```
fn parse(source: String) -> PersistentAST {
    let nodes = Arena::new(...)
    let strings = Arena::new(...)
    let root = parse_expr(source, nodes, strings)
    let result = convert_to_gc_managed(root, nodes, strings)
    nodes.reset()
    strings.reset()
    result
}
```

**Integration with incr library:**
When incr Memo nodes hold Refs into ASTArena, `Arena.reset()` must be
synchronized with Memo invalidation. Approach: tie `incr.generation` to
`Arena.generation` so that a Memo is automatically stale when its Arena resets.

### §8.3 CRDT: CRDTOpPool

**Purpose:** Efficiently batch-process remote CRDT operations.

```
struct CRDTOpPool {
    op_arena : Arena   // Temporary storage for operation batch
}
```

**Pattern:**

```
1. Receive batch of remote operations
2. Deserialize into op_arena
3. Apply to FugueTree (which lives under normal GC)
4. op_arena.reset()
```

The FugueTree itself remains GC-managed. Only the transient operation data
uses the arena. `MbBump` (all-backend) is likely sufficient here since
CRDT batch processing is not real-time-constrained.

### §8.4 incr: MemoTable

**Purpose:** Generation-based cache management for incremental computation.

The MemoTable does not necessarily need a physical Arena. It borrows only the
**generational index concept**:

```
struct MemoEntry[T] {
    value      : T
    generation : Int
}

fn is_fresh(entry: MemoEntry[T], current_gen: Int) -> Bool {
    entry.generation == current_gen
}
```

If memo computation results contain large temporary data structures, those
temporaries CAN be placed in an Arena for O(1) bulk release on generation
transition. But the MemoTable's own metadata (HashMap) stays under GC.

---

## §9 Safety Levels

```
Level 3 — Type safety (compile time)
    TypedRef[T] prevents cross-arena type confusion.

Level 2 — Generation safety (runtime check)
    Generational index detects use-after-reset.
    Return type: Option (None on stale access).

Level 1 — Bounds safety (runtime check)
    offset < capacity check in bump allocator.

Level 0 — Unsafe (no checks)
    Direct C-side read/write. For profiled DSP hot paths only.
```

**Policy:**
- Develop at Level 2–3. All access returns `Option`.
- Profile. Identify hot paths.
- Downgrade ONLY those hot paths to Level 0 with explicit `_unchecked` suffix.

```
fn Arena::get_checked(self, ref: Ref) -> Bytes?     // Level 2
fn Arena::get_unchecked(self, ref: Ref) -> Bytes     // Level 0
```

---

## §10 GrowableArena (Extension)

For parsers where input size is unknown, a single fixed-size Arena may not
suffice. GrowableArena chains multiple Arena chunks.

```
struct GrowableArena {
    chunks      : Array[Arena]
    mut current : Int
}

struct GrowableRef {
    chunk_index : Int
    ref         : Ref
}
```

**Behavior:**
- `alloc()`: Try current chunk. If full, create a new chunk and append.
- `reset()`: Reset all chunks, set current to 0.
- Access requires one extra indirection (chunk lookup).

**Priority:** Low. Start with fixed Arena. Add GrowableArena when needed.
DSP never needs it (buffer sizes are known). Parser and CRDT may need it.

---

## §11 Package Structure

```
arena/
├── core/
│   ├── ref.mbt              # Ref, TypedRef types
│   ├── arena.mbt            # Arena struct and core logic
│   └── storable.mbt         # Storable trait definition
│
├── bump/
│   ├── trait.mbt            # BumpAllocator trait
│   ├── mb_bump.mbt          # MbBump implementation
│   ├── c_bump.mbt           # CFFIBump MoonBit wrapper
│   └── c_bump.c             # C bump allocator implementation
│
├── gen_store/
│   ├── trait.mbt            # GenStore trait
│   ├── mb_gen.mbt           # MbGenStore implementation
│   ├── c_gen.mbt            # CGenStore MoonBit wrapper
│   └── c_gen.c              # C generation array implementation
│
├── config/
│   ├── debug.mbt            # Arena::new_debug  (Mb + Mb)
│   └── release.mbt          # Arena::new_release (C + C)
│
└── domain/
    ├── audio_buffer.mbt     # AudioBufferPool
    ├── ast_arena.mbt        # ASTArena
    └── ...
```

---

## §12 Implementation Roadmap

### Phase 1 — Minimal Viable Arena

Scope: MbBump + MbGenStore + Arena + Ref. All backends.

```
Deliverables:
  - MbBump with alloc/reset/capacity/used
  - MbGenStore with get/set/length/invalidate_all
  - Arena with alloc/is_valid/slot_offset/reset
  - Ref struct
  - Tests: alloc, get, reset, stale ref detection, capacity exhaustion
```

### Phase 2 — C-FFI Backend

Scope: CFFIBump + CGenStore + BumpImpl/GenStoreImpl enums. Native only.

```
Deliverables:
  - c_bump.c and CFFIBump wrapper with finalizer
  - c_gen.c and CGenStore wrapper with finalizer
  - Enum dispatch (BumpImpl, GenStoreImpl)
  - Arena::new_debug / new_release / new_hybrid
  - Benchmark: MbBump vs CFFIBump allocation throughput
  - Benchmark: MbGenStore vs CGenStore lookup throughput
```

### Phase 3 — Typed Arena

Scope: Storable trait + TypedRef + domain-specific arenas.

```
Deliverables:
  - Storable trait with byte_size/write_to/read_from
  - Storable implementations for Double, Int, AudioFrame
  - F64Arena, AudioArena (Pattern A specialization)
  - TypedRef[T]
  - Tests: type safety, round-trip serialization
```

### Phase 4 — Domain Integration

Scope: Wire arenas into DSP pipeline, parser, incr.

```
Deliverables:
  - AudioBufferPool integrated with Web Audio / VST callback
  - ASTArena integrated with incremental parser
  - incr generation synchronization with Arena.generation
  - Profiling: identify hot paths, downgrade to Level 0 where needed
```

### Phase 5 — Extensions (as needed)

```
Candidates:
  - GrowableArena for parser/CRDT
  - Code generation for TypedArena boilerplate
  - Memory usage statistics / visualization
  - DST (Deterministic Simulation Testing) integration
```

---

## §13 Summary Tables

### §13.1 All Types

| Name | Layer | Kind | Purpose |
|------|-------|------|---------|
| `BumpAllocator` | L1 | trait | Abstract byte-level alloc/reset |
| `MbBump` | L1 | struct | FixedArray[Byte]-backed bump allocator |
| `CFFIBump` | L1 | struct | C malloc-backed bump allocator |
| `GenStore` | L2 | trait | Abstract per-slot generation storage |
| `MbGenStore` | L2 | struct | Array[Int]-backed generation store |
| `CGenStore` | L2 | struct | C int*-backed generation store |
| `Ref` | L2 | struct | Generational index (index + generation) |
| `Arena` | L2 | struct | Slot-based allocator with generation tracking |
| `Storable` | L3 | trait | Fixed-size serialization to/from bytes |
| `TypedRef[T]` | L3 | struct | Type-tagged arena reference |
| `TypedArena[T]` | L3 | struct | Type-specialized arena |
| `BumpImpl` | Config | enum | Switches between MbBump and CFFIBump |
| `GenStoreImpl` | Config | enum | Switches between MbGenStore and CGenStore |
| `AudioBufferPool` | Domain | struct | DSP buffer pool |
| `ASTArena` | Domain | struct | Parser AST node arena |
| `CRDTOpPool` | Domain | struct | CRDT operation batch pool |
| `GrowableArena` | Extension | struct | Chunk-chained growable arena |
| `GrowableRef` | Extension | struct | Ref with chunk index |

### §13.2 All Traits

| Trait | Methods | Implementors |
|-------|---------|-------------|
| `BumpAllocator` | `alloc`, `reset`, `capacity`, `used` | `MbBump`, `CFFIBump` |
| `GenStore` | `get`, `set`, `length`, `invalidate_all` | `MbGenStore`, `CGenStore` |
| `Storable` | `byte_size`, `write_to`, `read_from` | `Double`, `Int`, user types |

### §13.3 Safety Level by Operation

| Operation | Level | Check | Return |
|-----------|-------|-------|--------|
| `Arena::alloc` | 1 | Bounds (count < max) | `Ref?` |
| `Arena::is_valid` | 2 | Generation match | `Bool` |
| `Arena::slot_offset` | 2 | Generation + bounds | `Int?` |
| `Arena::get_checked` | 2 | Generation + bounds | `Bytes?` |
| `Arena::get_unchecked` | 0 | None | `Bytes` |
| `TypedArena::alloc` | 3 | Type + bounds | `TypedRef[T]?` |
| `TypedArena::get` | 3 | Type + generation | `T?` |

---

## §14 Formal Semantics

```
Definitions:
    Arena = (bump, gen_store, G, count, slot_size)
    Ref   = (index, generation)

Validity:
    valid(r, a) ⟺ r.index < a.count
                  ∧ r.generation == a.G
                  ∧ a.gen_store[r.index] == r.generation

Allocation:
    alloc(a) =
        if a.count >= a.max_slots then None
        else
            let i = a.count
            a.bump.alloc(a.slot_size, align)
            a.gen_store[i] ← a.G
            a.count ← a.count + 1
            Some(Ref(i, a.G))

    Postcondition: valid(result, a)

Reset:
    reset(a) =
        a.bump.reset()
        a.G ← a.G + 1
        a.count ← 0

    Postcondition: ∀r. ¬valid(r, a)

Read:
    read(a, r) =
        if valid(r, a) then Some(a.bump.bytes_at(r.index * a.slot_size, a.slot_size))
        else None

Typed allocation:
    alloc_typed[T: Storable](a, v: T) =
        match alloc(a) with
        | None → None
        | Some(r) →
            v.write_to(a.bump, r.index * a.slot_size)
            Some(TypedRef[T](r))
```

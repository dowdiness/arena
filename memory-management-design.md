# MoonBit Memory Management Library — Design Document (v2)

> Target audience: Claude Code and human developers.
> Each section is self-contained. Cross-references use `§N` notation.
>
> **v2 changes:** Confirmed via C backend output that MoonBit uses
> monomorphization for trait-constrained generics. Enum dispatch design
> removed. Arena now uses generic type parameters `Arena[B, G]`.

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
5. **Zero-cost abstraction** — MoonBit monomorphizes generic functions; no vtable or enum match overhead.

---

## §3 Key Language Facts (Confirmed)

These were verified by inspecting actual C backend output from `moon build --target native`:

```
FACT 1: MoonBit monomorphizes trait-constrained generic functions.
        fn[T : Greet] say_hello(animal : T) generates separate
        say_hello$0 (Dog) and say_hello$1 (Cat) C functions.
        No vtable. No function pointers. Pure static dispatch.

FACT 2: struct Arena[B] (unconstrained type parameter) parses and works.

FACT 3: struct Arena[B, G] (multiple type parameters) works.

FACT 4: Trait constraints go on METHOD definitions, not struct definitions.
        fn[B : BumpAllocator] Arena::alloc(self : Arena[B]) -> Ref?

FACT 5: struct Arena[B : Trait] (constraint on struct) does NOT parse.

CONSEQUENCE: Arena[B, G] with constraints on methods gives us
             monomorphized, zero-cost backend switching with no
             enum dispatch and no vtable overhead.
```

---

## §4 Architecture Overview

```
╔═══════════════════════════════════════════════════════════════╗
║                     Domain Layer                              ║
║  AudioBufferPool   ASTArena   CRDTOpPool   MemoTable          ║
╠═══════════════════════════════════════════════════════════════╣
║                     Layer 3 — Typed Arena                     ║
║  TypedArena[B,G,T]   TypedRef[T]     Storable (trait)         ║
╠═══════════════════════════════════════════════════════════════╣
║                     Layer 2 — Generic Arena                   ║
║  Arena[B,G]        Ref              GenStore (trait)           ║
╠═══════════════════════════════════════════════════════════════╣
║                     Layer 1 — Physical Memory                 ║
║  BumpAllocator (trait)                                        ║
║    ├─ CFFIBump   (C malloc/mmap, GC-free, native only)       ║
║    └─ MbBump     (FixedArray[Byte], all backends)             ║
╚═══════════════════════════════════════════════════════════════╝
```

Data flows downward: Domain → L3 → L2 → L1.
Safety checks flow upward: L1 (bounds) → L2 (generation) → L3 (type).

**At compile time**, `Arena[MbBump, MbGenStore]` and `Arena[CFFIBump, CGenStore]`
generate completely separate, specialized C functions. Zero runtime dispatch cost.

---

## §5 Layer 1 — Physical Memory

### §5.1 Semantics

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

### §5.2 Trait: BumpAllocator

```moonbit
trait BumpAllocator {
  alloc(Self, size : Int, align : Int) -> Int?
  // Returns byte offset on success, None on capacity exhaustion.
  // Postcondition: returned offset is a multiple of `align`.

  reset(Self) -> Unit
  // Resets offset to 0. O(1).
  // Postcondition: used() == 0.

  capacity(Self) -> Int
  // Total capacity in bytes. Constant after creation.

  used(Self) -> Int
  // Bytes allocated since last reset.
}
```

### §5.3 Implementation A: CFFIBump (native only, GC-free)

Backed by `malloc`-allocated memory on the C side.
MoonBit holds an opaque pointer; a finalizer calls `free` on GC collection.

**C interface:**

```c
typedef struct { char* base; size_t offset; size_t capacity; } BumpArena;

BumpArena* bump_create(size_t capacity);
size_t     bump_alloc(BumpArena* a, size_t size, size_t align);
void       bump_reset(BumpArena* a);
void       bump_destroy(BumpArena* a);

void    bump_write_f64(BumpArena* a, size_t offset, double val);
double  bump_read_f64(BumpArena* a, size_t offset);
void    bump_write_i32(BumpArena* a, size_t offset, int32_t val);
int32_t bump_read_i32(BumpArena* a, size_t offset);
void    bump_memcpy(BumpArena* a, size_t dst, size_t src, size_t len);
```

**When to use:** DSP hot paths, any code path where GC pauses are unacceptable.

### §5.4 Implementation B: MbBump (all backends)

Backed by `FixedArray[Byte]` managed by MoonBit's GC.

```moonbit
struct MbBump {
  data : FixedArray[Byte]
  mut offset : Int
}
```

**When to use:** wasm-gc / JS backends, or native code where GC pauses are
tolerable (CRDT batch processing, non-real-time parsing).

---

## §6 Layer 2 — Generic Arena

### §6.1 Semantics

Layer 2 introduces **slots** (fixed-size regions within the bump buffer) and
**generational indices** that detect use-after-reset at runtime.

### §6.2 Type: Ref

```moonbit
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

### §6.3 Trait: GenStore

Stores per-slot generation numbers. Abstracted to allow MoonBit/C switching.

```moonbit
trait GenStore {
  get(Self, index : Int) -> Int
  set(Self, index : Int, generation : Int) -> Unit
  length(Self) -> Int
}
```

**Implementations:**

| Name | Backing storage | GC involvement | Target |
|------|----------------|----------------|--------|
| `MbGenStore` | `Array[Int]` | Yes (GC-managed) | All backends |
| `CGenStore` | C `int*` array | No | Native only |

### §6.4 Type: Arena[B, G]

```moonbit
struct Arena[B, G] {
  bump       : B
  gen_store  : G
  mut generation : Int
  mut count  : Int
  slot_size  : Int
  max_slots  : Int
}
```

**Operations (constraints on methods, not struct):**

```moonbit
fn[B : BumpAllocator, G : GenStore] Arena::alloc(self : Arena[B, G]) -> Ref? {
  if self.count >= self.max_slots {
    return None
  }
  let size = self.slot_size
  let align = 8
  match self.bump.alloc(size, align) {
    None => None
    Some(offset) => {
      let index = self.count
      self.gen_store.set(index, self.generation)
      self.count += 1
      Some({ index, generation: self.generation })
    }
  }
}

fn[B : BumpAllocator, G : GenStore] Arena::is_valid(
  self : Arena[B, G], ref : Ref
) -> Bool {
  ref.generation == self.generation
  && ref.index < self.count
  && self.gen_store.get(ref.index) == ref.generation
}

fn[B : BumpAllocator, G : GenStore] Arena::slot_offset(
  self : Arena[B, G], ref : Ref
) -> Int? {
  if self.is_valid(ref) {
    Some(ref.index * self.slot_size)
  } else {
    None
  }
}

fn[B : BumpAllocator, G : GenStore] Arena::reset(self : Arena[B, G]) -> Unit {
  self.bump.reset()
  self.generation += 1
  self.count = 0
  // gen_store is NOT cleared — lazy invalidation.
  // Old entries are stale because ref.generation != self.generation.
}
```

### §6.5 Lazy Invalidation on Reset

```
reset() is O(1):
  - bump.reset()         // reset offset to 0
  - generation += 1      // logically invalidates all existing Refs
  - count = 0            // reset slot counter

alloc() only writes the current generation to the NEW slot.
is_valid() rejects old refs because ref.generation != self.generation.

No need to clear gen_store on reset — critical for DSP block boundaries.
```

### §6.6 Monomorphization in Action

When user code instantiates the two configurations:

```moonbit
let debug_arena : Arena[MbBump, MbGenStore] = ...
let release_arena : Arena[CFFIBump, CGenStore] = ...
```

The compiler generates (in the C output):

```c
// Fully specialized — no indirection, no match, no vtable
Ref* Arena_MbBump_MbGenStore_alloc(Arena_MbBump_MbGenStore* self) { ... }
Ref* Arena_CFFIBump_CGenStore_alloc(Arena_CFFIBump_CGenStore* self) { ... }
```

Each call to `self.bump.alloc(...)` is inlined as a direct call to the
concrete implementation. The C compiler can then further inline and optimize.

---

## §7 Layer 3 — Typed Arena

### §7.1 Trait: Storable

```moonbit
trait Storable {
  byte_size() -> Int
  // Fixed size in bytes. Same for all instances of a given type.

  write_to(Self, bump : BumpImpl, offset : Int) -> Unit
  // Serialize self into bump buffer at the given offset.

  read_from(bump : BumpImpl, offset : Int) -> Self
  // Deserialize a value from bump buffer at the given offset.
}
```

**Note on Storable's bump parameter:** Since `write_to` and `read_from` need
to work with the bump allocator, they take the concrete bump type. This means
Storable implementations are tied to a specific BumpAllocator implementation.

Alternative: make Storable itself generic:

```moonbit
// Option A: Storable is bump-agnostic (uses abstract read/write helpers)
trait Storable {
  byte_size() -> Int
  write_bytes(Self, FixedArray[Byte], offset : Int) -> Unit
  read_bytes(FixedArray[Byte], offset : Int) -> Self
}

// Option B: Storable is generic over bump type
// (may hit MoonBit trait limitations)
```

**Recommendation:** Start with Option A (byte-array based). For CFFIBump,
provide a helper that copies between C memory and a temporary FixedArray[Byte].
Optimize later if profiling shows this is a bottleneck.

### §7.2 Type: TypedRef[T]

```moonbit
struct TypedRef[T] {
  ref : Ref
}
```

Phantom type parameter `T` prevents mixing references across arenas of
different element types at compile time. Zero runtime cost — it is just a `Ref`.

### §7.3 TypedArena[B, G, T] — Pattern A (Manual Specialization)

Since MoonBit's trait limitations may prevent fully generic TypedArena,
use manual specialization per domain type:

```moonbit
struct F64Arena[B, G] {
  arena : Arena[B, G]
}

fn[B : BumpAllocator, G : GenStore] F64Arena::alloc(
  self : F64Arena[B, G], value : Double
) -> TypedRef[Double]? {
  match self.arena.alloc() {
    None => None
    Some(ref) => {
      let offset = ref.index * self.arena.slot_size
      // write value at offset (implementation depends on B)
      Some({ ref })
    }
  }
}
```

**Recommendation:** Start with 2-3 manual specializations (Double, AudioFrame,
ASTNode). Extract common patterns for code generation later.

---

## §8 Domain Layer — Usage Patterns

### §8.1 DSP: AudioBufferPool

```moonbit
struct AudioBufferPool[B, G] {
  arena             : Arena[B, G]
  frames_per_buffer : Int
  channels          : Int
}
```

**Lifecycle per audio callback:**

```
1. arena.reset()                         // O(1), invalidates all prior Refs
2. let temp = arena.alloc()              // O(1), bump pointer advance
3. DSP processing via direct read/write  // zero GC, zero alloc
4. Callback returns                      // nothing to free
```

**Concrete instantiation:**

```moonbit
// Real-time audio — native only, GC-free
let pool : AudioBufferPool[CFFIBump, CGenStore] = ...

// Offline rendering — all backends
let pool : AudioBufferPool[MbBump, MbGenStore] = ...
```

Both compile to fully specialized code with zero dispatch overhead.

### §8.2 Parser: ASTArena

```moonbit
struct ASTArena[B, G] {
  node_arena   : Arena[B, G]
  string_arena : Arena[B, G]
}
```

**AST node representation:**

```
BinaryExpr = { op: Int(4B), left: Ref(8B), right: Ref(8B) } = 20B → 24B aligned

Strings: written directly into string_arena as bytes.
AST nodes hold StringRef = { offset: Int, length: Int } = 8B.
```

**Phase lifecycle:**

```moonbit
fn parse[B : BumpAllocator, G : GenStore](
  source : String, nodes : Arena[B, G], strings : Arena[B, G]
) -> PersistentAST {
  // ... parse into arenas ...
  let result = convert_to_gc_managed(root, nodes, strings)
  nodes.reset()
  strings.reset()
  result
}
```

### §8.3 CRDT: CRDTOpPool

```moonbit
struct CRDTOpPool[B, G] {
  op_arena : Arena[B, G]
}
```

Likely sufficient with `Arena[MbBump, MbGenStore]` (all-backend, not
real-time-constrained).

### §8.4 incr: MemoTable

Borrows only the generational index concept. No physical Arena needed.
If memo results contain large temporaries, those can optionally go into
an Arena for O(1) bulk release on generation transition.

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

```moonbit
fn[B : BumpAllocator, G : GenStore] Arena::get_checked(
  self : Arena[B, G], ref : Ref
) -> Bytes?

fn[B : BumpAllocator, G : GenStore] Arena::get_unchecked(
  self : Arena[B, G], ref : Ref
) -> Bytes
```

---

## §10 GrowableArena (Extension)

```moonbit
struct GrowableArena[B, G] {
  chunks      : Array[Arena[B, G]]
  mut current : Int
}

struct GrowableRef {
  chunk_index : Int
  ref         : Ref
}
```

**Priority:** Low. Start with fixed Arena. DSP never needs it.

---

## §11 Package Structure

```
arena/
├── core/
│   ├── ref.mbt              # Ref, TypedRef types
│   ├── arena.mbt            # Arena[B, G] struct and methods
│   └── storable.mbt         # Storable trait
│
├── bump/
│   ├── trait.mbt            # BumpAllocator trait
│   ├── mb_bump.mbt          # MbBump (FixedArray[Byte], all backends)
│   ├── c_bump.mbt           # CFFIBump (C-FFI wrapper, native only)
│   └── c_bump.c             # C bump allocator implementation
│
├── gen_store/
│   ├── trait.mbt            # GenStore trait
│   ├── mb_gen.mbt           # MbGenStore (Array[Int], all backends)
│   ├── c_gen.mbt            # CGenStore (C-FFI wrapper, native only)
│   └── c_gen.c              # C generation array implementation
│
└── domain/
    ├── audio_buffer.mbt     # AudioBufferPool[B, G]
    ├── ast_arena.mbt        # ASTArena[B, G]
    └── ...
```

**Note:** No `config/` directory needed. Backend selection is purely a matter
of which type parameters the user provides at instantiation time.

---

## §12 Implementation Roadmap

### Phase 1 — Minimal Viable Arena

```
Deliverables:
  - BumpAllocator trait
  - MbBump implementing BumpAllocator
  - GenStore trait
  - MbGenStore implementing GenStore
  - Arena[B, G] with alloc/is_valid/slot_offset/reset
  - Ref struct
  - Tests: alloc, is_valid, reset, stale ref detection, capacity exhaustion
  - Target: all backends (wasm-gc, JS, native)
```

### Phase 2 — C-FFI Backend

```
Deliverables:
  - c_bump.c + CFFIBump implementing BumpAllocator
  - c_gen.c + CGenStore implementing GenStore
  - Arena[CFFIBump, CGenStore] works out of the box (no new Arena code!)
  - Verify monomorphization in C output
  - Benchmark: Arena[MbBump, MbGenStore] vs Arena[CFFIBump, CGenStore]
```

### Phase 3 — Typed Arena

```
Deliverables:
  - Storable trait
  - Storable for Double, Int
  - F64Arena[B, G], AudioFrameArena[B, G] (manual specialization)
  - TypedRef[T]
  - Tests: type safety, round-trip serialization
```

### Phase 4 — Domain Integration

```
Deliverables:
  - AudioBufferPool[CFFIBump, CGenStore] in DSP pipeline
  - ASTArena[MbBump, MbGenStore] in parser
  - incr generation synchronization
  - Profile and downgrade hot paths to Level 0
```

### Phase 5 — Extensions (as needed)

```
  - GrowableArena[B, G]
  - Code generation for TypedArena boilerplate
  - Memory statistics / visualization
  - DST integration
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
| `Arena[B, G]` | L2 | struct | Slot-based allocator, generic over backend |
| `Storable` | L3 | trait | Fixed-size serialization to/from bytes |
| `TypedRef[T]` | L3 | struct | Type-tagged arena reference |
| `F64Arena[B, G]` | L3 | struct | Double-specialized typed arena |
| `AudioBufferPool[B, G]` | Domain | struct | DSP buffer pool |
| `ASTArena[B, G]` | Domain | struct | Parser AST node arena |
| `CRDTOpPool[B, G]` | Domain | struct | CRDT operation batch pool |
| `GrowableArena[B, G]` | Extension | struct | Chunk-chained growable arena |
| `GrowableRef` | Extension | struct | Ref with chunk index |

### §13.2 All Traits

| Trait | Methods | Implementors |
|-------|---------|-------------|
| `BumpAllocator` | `alloc`, `reset`, `capacity`, `used` | `MbBump`, `CFFIBump` |
| `GenStore` | `get`, `set`, `length` | `MbGenStore`, `CGenStore` |
| `Storable` | `byte_size`, `write_bytes`, `read_bytes` | `Double`, `Int`, user types |

### §13.3 Safety Level by Operation

| Operation | Level | Check | Return |
|-----------|-------|-------|--------|
| `Arena::alloc` | 1 | Bounds (count < max) | `Ref?` |
| `Arena::is_valid` | 2 | Generation match | `Bool` |
| `Arena::slot_offset` | 2 | Generation + bounds | `Int?` |
| `Arena::get_checked` | 2 | Generation + bounds | `Bytes?` |
| `Arena::get_unchecked` | 0 | None | `Bytes` |

### §13.4 Backend Configurations

| Configuration | B | G | Target | GC-free | Use case |
|--------------|---|---|--------|---------|----------|
| Debug | `MbBump` | `MbGenStore` | All backends | No | Development, wasm-gc, JS |
| Release | `CFFIBump` | `CGenStore` | Native only | Yes | Real-time DSP, perf-critical |
| Hybrid | `CFFIBump` | `MbGenStore` | Native only | Partial | GC-free memory, MoonBit-side checks |

All three compile to fully specialized code. No runtime cost for switching.

---

## §14 Formal Semantics

```
Definitions:
    Arena[B, G] = (bump: B, gen_store: G, G_current: Int, count: Int, slot_size: Int)
    Ref         = (index: Int, generation: Int)

Validity:
    valid(r, a) ⟺ r.index < a.count
                  ∧ r.generation == a.G_current
                  ∧ a.gen_store[r.index] == r.generation

Allocation:
    alloc(a) =
        if a.count >= a.max_slots then None
        else
            let i = a.count
            a.bump.alloc(a.slot_size, align)
            a.gen_store[i] ← a.G_current
            a.count ← a.count + 1
            Some(Ref(i, a.G_current))

    Postcondition: valid(result, a)

Reset:
    reset(a) =
        a.bump.reset()
        a.G_current ← a.G_current + 1
        a.count ← 0

    Postcondition: ∀r. ¬valid(r, a)

Read:
    read(a, r) =
        if valid(r, a) then Some(a.bump.bytes_at(r.index * a.slot_size, a.slot_size))
        else None

Monomorphization guarantee:
    ∀ concrete types B₁, G₁, B₂, G₂:
      Arena[B₁, G₁]::alloc and Arena[B₂, G₂]::alloc
      compile to separate, fully-specialized C functions
      with zero indirection.
```

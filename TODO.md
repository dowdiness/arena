# TODO

Task checklist for the Arena allocator implementation.
See `ROADMAP.md` for detailed design rationale and `memory-management-design.md` for the full spec.

---

## Phase 1 — Minimal Viable Arena

### 1.1 MbBump (bump allocator)

- [x] Create `mb_bump.mbt` with `MbBump` struct
- [x] Implement `MbBump::new(capacity: Int) -> MbBump`
- [x] Implement `MbBump::alloc(self, size: Int, align: Int) -> Int?` with alignment
- [x] Implement `MbBump::reset(self) -> Unit`
- [x] Implement `MbBump::capacity(self) -> Int`
- [x] Implement `MbBump::used(self) -> Int`
- [x] Implement typed read/write helpers (`write_int32`, `read_int32`, `write_double`, `read_double`)
- [x] Create `mb_bump_test.mbt` with tests:
  - [x] Sequential allocation with correct alignment
  - [x] Capacity exhaustion returns None
  - [x] Reset brings used() to 0
  - [x] Alloc works after reset
  - [x] Int32 read/write round-trip
  - [x] Double read/write round-trip
  - [x] Zero/negative alignment rejection
  - [x] Non-positive size rejection
  - [x] Overflowing size rejection
  - [x] Overflowing alignment rejection
  - [x] Negative capacity clamping
  - [x] Out-of-bounds typed accessor rejection

### 1.2 MbGenStore (generation storage)

- [x] Create `mb_gen_store.mbt` with `MbGenStore` struct
- [x] Implement `MbGenStore::new(slot_count: Int) -> MbGenStore`
- [x] Implement `MbGenStore::get(self, index: Int) -> Int`
- [x] Implement `MbGenStore::set(self, index: Int, generation: Int) -> Unit`
- [x] Implement `MbGenStore::length(self) -> Int`
- [x] Create `mb_gen_store_test.mbt` with tests:
  - [x] Initial values are 0
  - [x] get/set round-trip
  - [x] Independent slot updates
  - [x] Negative slot count clamping

### 1.3 Ref (generational index)

- [x] Create `ref.mbt` with `Ref` struct (index + generation)
- [x] Derive `Eq` and `Show`

### 1.4 Arena (core allocator)

- [x] Replace placeholder code in `arena.mbt` with `Arena` struct
- [x] Implement `Arena::new(slot_count: Int, slot_size: Int) -> Arena`
- [x] Implement `Arena::alloc(self) -> Ref?`
- [x] Implement `Arena::is_valid(self, aref: Ref) -> Bool` (validity predicate)
- [x] Implement `Arena::slot_offset(self, aref: Ref) -> Int?`
- [x] Implement `Arena::reset(self) -> Unit` (O(1) lazy invalidation)
- [x] Implement accessor methods (`get_generation`, `get_count`, `get_max_slots`)
- [x] Implement typed read/write through Arena (`write_int32`, `read_int32`, `write_double`, `read_double`)
- [x] Replace placeholder tests in `arena_test.mbt`:
  - [x] Alloc returns valid Refs
  - [x] is_valid true for fresh Refs
  - [x] is_valid false after reset (stale ref detection)
  - [x] Multiple alloc/reset cycles
  - [x] Capacity exhaustion returns None
  - [x] slot_offset correctness
  - [x] Read/write round-trip through Arena
  - [x] Stale ref write returns false / read returns None
  - [x] Field offset bounds checking
  - [x] Negative index rejection
  - [x] Overflowing field offset rejection
  - [x] Capacity overflow handling
  - [x] Non-positive constructor input handling
  - [x] Bump alloc failure propagation
  - [x] Generation counter exhaustion (abort)

### 1.5 Cleanup

- [x] Remove `fib` and `sum` from `arena.mbt`
- [x] Remove `fib` and `sum` tests from `arena_test.mbt`
- [x] Update `cmd/main/main.mbt` to use Arena API
- [x] Run `moon info && moon fmt`
- [x] Run `moon test` — all 33 tests pass
- [x] Review `.mbti` diff for expected public API

---

## Phase 2 — Backend Abstraction & C-FFI

Design changed from enum dispatch to generic type params with monomorphization.
Traits stay in root package; C-FFI in `cffi/` sub-package.

### 2a Traits & Generic Arena

- [x] Define `BumpAllocator` trait in `bump_allocator.mbt`
- [x] Define `GenStore` trait in `gen_store_trait.mbt`
- [x] Implement `BumpAllocator` for `MbBump` (trait impl blocks)
- [x] Implement `GenStore` for `MbGenStore` (trait impl blocks)
- [x] Genericize `Arena` to `Arena[B, G]` with trait constraints
- [x] Add `Arena::new_with[B, G]` generic constructor
- [x] Keep `Arena::new` backward-compatible (returns `Arena[MbBump, MbGenStore]`)
- [x] Validate `new_with` preconditions (empty bump, clamp max_slots)
- [x] All 36 existing tests pass on wasm-gc

### 2b C-FFI Backend (native only)

- [x] Create `cffi/` sub-package with `moon.pkg.json` (targets conditional compilation)
- [x] Write `cffi/c_bump.c` (C bump allocator)
- [x] Write `cffi/c_bump.mbt` (`CFFIBump` FFI wrapper + `BumpAllocator` impl)
- [x] Write `cffi/c_gen.c` (C generation array)
- [x] Write `cffi/c_gen.mbt` (`CGenStore` FFI wrapper + `GenStore` impl)
- [x] Write `cffi/cffi.mbt` (`new_arena()` convenience constructor)
- [x] Safety: null-pointer checks on C allocation, `destroyed` flag, bounds checks before FFI
- [x] Manual `destroy()` methods for native memory cleanup
- [x] CFFIBump tests (14 tests mirroring MbBump suite + destroy/null safety)
- [x] CGenStore tests (11 tests mirroring MbGenStore suite + destroy/bounds safety)
- [x] Arena[CFFIBump, CGenStore] integration tests (10 tests)
- [x] All 71 tests pass on native target

### 2.x Benchmarks

- [ ] MbBump vs CFFIBump allocation throughput
- [ ] MbGenStore vs CGenStore lookup throughput
- [ ] Arena alloc/reset cycle timing

---

## Phase 3 — Typed Arena

### 3.1 Storable trait

- [ ] Define `Storable` trait (`byte_size`, `write_to`, `read_from`)
- [ ] Implement `Storable` for `Double`
- [ ] Implement `Storable` for `Int`

### 3.2 TypedRef[T]

- [ ] Define `TypedRef[T]` struct wrapping `Ref`
- [ ] Derive or implement `Eq` and `Show`

### 3.3 Manual specialization (Pattern A)

- [ ] Implement `F64Arena` (alloc, get, set, reset)
- [ ] Implement `I32Arena` (alloc, get, set, reset)
- [ ] Define `AudioFrame` struct
- [ ] Implement `Storable` for `AudioFrame`
- [ ] Implement `AudioArena`

### 3.4 Tests

- [ ] Round-trip serialization for Double, Int, AudioFrame
- [ ] TypedRef type safety (compile-time check)
- [ ] Stale TypedRef detection

---

## Phase 4 — Domain Integration

### 4.1 AudioBufferPool

- [ ] Define `AudioBufferPool` struct
- [ ] Implement per-callback lifecycle (reset/alloc/process)
- [ ] Integration test simulating audio callback pattern

### 4.2 ASTArena

- [ ] Define `ASTArena` struct (node_arena + string_arena)
- [ ] Define `StringRef` struct
- [ ] Implement phase lifecycle (parse/convert/reset)
- [ ] Tests with mock AST nodes

### 4.3 incr integration

- [ ] Design generation synchronization mechanism
- [ ] Implement MemoEntry with generation field
- [ ] Tests: staleness detection on Arena reset

---

## Phase 5 — Extensions

- [ ] GrowableArena (chunk-chained arena)
- [ ] GrowableRef (Ref with chunk_index)
- [ ] `get_unchecked` / `set_unchecked` (Level 0 unsafe access)
- [ ] Memory usage statistics
- [ ] Code generation for TypedArena boilerplate

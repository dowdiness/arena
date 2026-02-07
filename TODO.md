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

### 2.1 Package restructuring

- [ ] Create `bump/` package with `moon.pkg.json`
- [ ] Create `gen_store/` package with `moon.pkg.json`
- [ ] Create `core/` package with `moon.pkg.json`
- [ ] Move MbBump to `bump/mb_bump.mbt`
- [ ] Move MbGenStore to `gen_store/mb_gen.mbt`
- [ ] Move Ref and Arena to `core/`
- [ ] Update imports and verify `moon check` passes

### 2.2 Traits

- [ ] Define `BumpAllocator` trait in `bump/trait.mbt`
- [ ] Implement `BumpAllocator` for `MbBump`
- [ ] Define `GenStore` trait in `gen_store/trait.mbt`
- [ ] Implement `GenStore` for `MbGenStore`

### 2.3 CFFIBump

- [ ] Write `bump/c_bump.c` (C bump allocator)
- [ ] Write `bump/c_bump.mbt` (FFI wrapper)
- [ ] Add finalizer for `bump_destroy`
- [ ] Implement `BumpAllocator` for `CFFIBump`
- [ ] Tests: same suite as MbBump

### 2.4 CGenStore

- [ ] Write `gen_store/c_gen.c` (C generation array)
- [ ] Write `gen_store/c_gen.mbt` (FFI wrapper)
- [ ] Add finalizer
- [ ] Implement `GenStore` for `CGenStore`
- [ ] Tests: same suite as MbGenStore

### 2.5 Enum dispatch & configuration

- [ ] Define `BumpImpl` enum in `core/`
- [ ] Define `GenStoreImpl` enum in `core/`
- [ ] Update Arena to use enum dispatch
- [ ] Implement `Arena::new_debug` (Mb + Mb)
- [ ] Implement `Arena::new_release` (C + C)
- [ ] Implement `Arena::new_hybrid` (C + Mb)

### 2.6 Benchmarks

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

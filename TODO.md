# TODO

Task checklist for the Arena allocator implementation.
See `ROADMAP.md` for detailed design rationale and `memory-management-design.md` for the full spec.

---

## Phase 1 — Minimal Viable Arena

### 1.1 MbBump (bump allocator)

- [ ] Create `mb_bump.mbt` with `MbBump` struct
- [ ] Implement `MbBump::new(capacity: Int) -> MbBump`
- [ ] Implement `MbBump::alloc(self, size: Int, align: Int) -> Int?` with alignment
- [ ] Implement `MbBump::reset(self) -> Unit`
- [ ] Implement `MbBump::capacity(self) -> Int`
- [ ] Implement `MbBump::used(self) -> Int`
- [ ] Implement byte-level read/write helpers (`write_int32`, `read_int32`, `write_double`, `read_double`)
- [ ] Create `mb_bump_test.mbt` with tests:
  - [ ] Sequential allocation with correct alignment
  - [ ] Capacity exhaustion returns None
  - [ ] Reset brings used() to 0
  - [ ] Alloc works after reset
  - [ ] Int32 read/write round-trip
  - [ ] Double read/write round-trip

### 1.2 MbGenStore (generation storage)

- [ ] Create `mb_gen_store.mbt` with `MbGenStore` struct
- [ ] Implement `MbGenStore::new(slot_count: Int) -> MbGenStore`
- [ ] Implement `MbGenStore::get(self, index: Int) -> Int`
- [ ] Implement `MbGenStore::set(self, index: Int, generation: Int) -> Unit`
- [ ] Implement `MbGenStore::length(self) -> Int`
- [ ] Create `mb_gen_store_test.mbt` with tests:
  - [ ] Initial values are 0
  - [ ] get/set round-trip
  - [ ] Independent slot updates

### 1.3 Ref (generational index)

- [ ] Create `ref.mbt` with `Ref` struct (index + generation)
- [ ] Derive or implement `Eq` and `Show`

### 1.4 Arena (core allocator)

- [ ] Replace placeholder code in `arena.mbt` with `Arena` struct
- [ ] Implement `Arena::new(slot_count: Int, slot_size: Int) -> Arena`
- [ ] Implement `Arena::alloc(self) -> Ref?`
- [ ] Implement `Arena::is_valid(self, ref: Ref) -> Bool` (validity predicate)
- [ ] Implement `Arena::slot_offset(self, ref: Ref) -> Int?`
- [ ] Implement `Arena::reset(self) -> Unit` (O(1) lazy invalidation)
- [ ] Implement accessor methods (`generation`, `count`, `capacity`)
- [ ] Implement typed read/write through Arena (`write_int32`, `read_int32`, `write_double`, `read_double`)
- [ ] Replace placeholder tests in `arena_test.mbt`:
  - [ ] Alloc returns valid Refs
  - [ ] is_valid true for fresh Refs
  - [ ] is_valid false after reset (stale ref detection)
  - [ ] Multiple alloc/reset cycles
  - [ ] Capacity exhaustion returns None
  - [ ] slot_offset correctness
  - [ ] Read/write round-trip through Arena
  - [ ] Stale ref write returns false / read returns None

### 1.5 Cleanup

- [ ] Remove `fib` and `sum` from `arena.mbt`
- [ ] Remove `fib` and `sum` tests from `arena_test.mbt`
- [ ] Update `cmd/main/main.mbt` to use Arena API
- [ ] Run `moon info && moon fmt`
- [ ] Run `moon test` — all pass
- [ ] Review `.mbti` diff for expected public API

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

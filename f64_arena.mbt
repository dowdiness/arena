///|
pub struct F64Arena[B, G] {
  arena : Arena[B, G]
}

///|
pub fn F64Arena::new(slot_count : Int) -> F64Arena[MbBump, MbGenStore] {
  { arena: Arena::new(slot_count, 8) }
}

///|
pub fn[B : BumpAllocator, G : GenStore] F64Arena::new_with(
  bump : B,
  gen_store : G,
  max_slots : Int,
) -> F64Arena[B, G] {
  { arena: Arena::new_with(bump, gen_store, 8, max_slots) }
}

///|
/// Allocates and initializes a new slot.
///
/// If backend allocation succeeds but the initialization write fails, this is
/// treated as a `BumpAllocator` contract violation and aborts.
pub fn[B : BumpAllocator, G : GenStore] F64Arena::alloc(
  self : F64Arena[B, G],
  value : Double,
) -> TypedRef[Double]? {
  match self.arena.alloc() {
    None => None
    Some(r) =>
      if self.arena.write_double(r, 0, value) {
        Some(TypedRef::{ inner: r })
      } else {
        abort("F64Arena::alloc: BumpAllocator contract violation")
      }
  }
}

///|
pub fn[B : BumpAllocator, G : GenStore] F64Arena::get(
  self : F64Arena[B, G],
  tref : TypedRef[Double],
) -> Double? {
  self.arena.read_double(tref.inner, 0)
}

///|
/// Updates an existing typed reference.
///
/// Returns `false` for recoverable runtime conditions such as stale/invalid
/// references.
pub fn[B : BumpAllocator, G : GenStore] F64Arena::set(
  self : F64Arena[B, G],
  tref : TypedRef[Double],
  value : Double,
) -> Bool {
  self.arena.write_double(tref.inner, 0, value)
}

///|
pub fn[B : BumpAllocator, G] F64Arena::reset(self : F64Arena[B, G]) -> Unit {
  self.arena.reset()
}

///|
pub fn[B, G : GenStore] F64Arena::is_valid(
  self : F64Arena[B, G],
  tref : TypedRef[Double],
) -> Bool {
  self.arena.is_valid(tref.inner)
}

///|
pub struct I32Arena[B, G] {
  arena : Arena[B, G]
}

///|
pub fn I32Arena::new(slot_count : Int) -> I32Arena[MbBump, MbGenStore] {
  { arena: Arena::new(slot_count, 4) }
}

///|
pub fn[B : BumpAllocator, G : GenStore] I32Arena::new_with(
  bump : B,
  gen_store : G,
  max_slots : Int,
) -> I32Arena[B, G] {
  { arena: Arena::new_with(bump, gen_store, 4, max_slots) }
}

///|
/// Allocates and initializes a new slot.
///
/// If backend allocation succeeds but the initialization write fails, this is
/// treated as a `BumpAllocator` contract violation and aborts.
pub fn[B : BumpAllocator, G : GenStore] I32Arena::alloc(
  self : I32Arena[B, G],
  value : Int,
) -> TypedRef[Int]? {
  match self.arena.alloc() {
    None => None
    Some(r) =>
      if self.arena.write_int32(r, 0, value) {
        Some(TypedRef::{ inner: r })
      } else {
        abort("I32Arena::alloc: BumpAllocator contract violation")
      }
  }
}

///|
pub fn[B : BumpAllocator, G : GenStore] I32Arena::get(
  self : I32Arena[B, G],
  tref : TypedRef[Int],
) -> Int? {
  self.arena.read_int32(tref.inner, 0)
}

///|
/// Updates an existing typed reference.
///
/// Returns `false` for recoverable runtime conditions such as stale/invalid
/// references.
pub fn[B : BumpAllocator, G : GenStore] I32Arena::set(
  self : I32Arena[B, G],
  tref : TypedRef[Int],
  value : Int,
) -> Bool {
  self.arena.write_int32(tref.inner, 0, value)
}

///|
pub fn[B : BumpAllocator, G] I32Arena::reset(self : I32Arena[B, G]) -> Unit {
  self.arena.reset()
}

///|
pub fn[B, G : GenStore] I32Arena::is_valid(
  self : I32Arena[B, G],
  tref : TypedRef[Int],
) -> Bool {
  self.arena.is_valid(tref.inner)
}

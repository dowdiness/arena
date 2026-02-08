///|
pub struct AudioArena[B, G] {
  arena : Arena[B, G]
}

///|
pub fn AudioArena::new(slot_count : Int) -> AudioArena[MbBump, MbGenStore] {
  { arena: Arena::new(slot_count, 16) }
}

///|
pub fn[B : BumpAllocator, G : GenStore] AudioArena::new_with(
  bump : B,
  gen_store : G,
  max_slots : Int,
) -> AudioArena[B, G] {
  { arena: Arena::new_with(bump, gen_store, 16, max_slots) }
}

///|
/// Allocates and initializes a new slot.
///
/// If backend allocation succeeds but either initialization write fails, this
/// is treated as a `BumpAllocator` contract violation and aborts.
pub fn[B : BumpAllocator, G : GenStore] AudioArena::alloc(
  self : AudioArena[B, G],
  frame : AudioFrame,
) -> TypedRef[AudioFrame]? {
  match self.arena.alloc() {
    None => None
    Some(r) => {
      if not(self.arena.write_double(r, 0, frame.left)) {
        abort("AudioArena::alloc: BumpAllocator contract violation")
      }
      if self.arena.write_double(r, 8, frame.right) {
        Some(TypedRef::{ inner: r })
      } else {
        abort("AudioArena::alloc: BumpAllocator contract violation")
      }
    }
  }
}

///|
pub fn[B : BumpAllocator, G : GenStore] AudioArena::get(
  self : AudioArena[B, G],
  tref : TypedRef[AudioFrame],
) -> AudioFrame? {
  match self.arena.read_double(tref.inner, 0) {
    None => None
    Some(left) =>
      match self.arena.read_double(tref.inner, 8) {
        None => None
        Some(right) => Some({ left, right })
      }
  }
}

///|
/// Updates an existing typed reference.
///
/// Returns `false` for recoverable runtime conditions such as stale/invalid
/// references.
pub fn[B : BumpAllocator, G : GenStore] AudioArena::set(
  self : AudioArena[B, G],
  tref : TypedRef[AudioFrame],
  frame : AudioFrame,
) -> Bool {
  if not(self.arena.write_double(tref.inner, 0, frame.left)) {
    return false
  }
  self.arena.write_double(tref.inner, 8, frame.right)
}

///|
pub fn[B : BumpAllocator, G] AudioArena::reset(self : AudioArena[B, G]) -> Unit {
  self.arena.reset()
}

///|
pub fn[B, G : GenStore] AudioArena::is_valid(
  self : AudioArena[B, G],
  tref : TypedRef[AudioFrame],
) -> Bool {
  self.arena.is_valid(tref.inner)
}

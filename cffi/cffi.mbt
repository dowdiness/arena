///|
pub fn new_arena(
  slot_count : Int,
  slot_size : Int,
) -> @arena.Arena[CFFIBump, CGenStore] {
  let (capacity, max_slots) = if slot_count <= 0 || slot_size <= 0 {
    (0, 0)
  } else if slot_count > @int.max_value / slot_size {
    (0, 0)
  } else {
    (slot_count * slot_size, slot_count)
  }
  @arena.Arena::new_with(
    CFFIBump::new(capacity),
    CGenStore::new(max_slots),
    slot_size,
    max_slots,
  )
}

///|
test "Arena::is_valid rejects negative index" {
  let arena = Arena::new(4, 8)
  arena.alloc() |> ignore
  let bad = Ref::{ index: -1, generation: arena.generation }
  inspect(arena.is_valid(bad), content="false")
  inspect(arena.slot_offset(bad), content="None")
}

///|
test "Arena::new handles capacity overflow gracefully" {
  // 65536 * 65536 overflows 32-bit Int
  let arena = Arena::new(65536, 65536)
  inspect(arena.get_max_slots(), content="0")
  inspect(arena.alloc(), content="None")
  // 50000 * 50000 also overflows
  let arena2 = Arena::new(50000, 50000)
  inspect(arena2.get_max_slots(), content="0")
  inspect(arena2.alloc(), content="None")
}

///|
test "Arena::new handles non-positive inputs" {
  let arena = Arena::new(-1, 8)
  inspect(arena.get_max_slots(), content="0")
  let arena2 = Arena::new(4, 0)
  inspect(arena2.get_max_slots(), content="0")
}

///|
test "Arena::write_int32 rejects overflowing field_offset" {
  let arena = Arena::new(4, 8)
  let r = arena.alloc().unwrap()
  inspect(arena.write_int32(r, @int.max_value, 42), content="false")
  inspect(arena.read_int32(r, @int.max_value), content="None")
}

///|
test "Arena::new_with clamps max_slots to gen_store length" {
  // gen_store has 2 slots, but caller asks for max_slots=10
  let arena = Arena::new_with(MbBump::new(80), MbGenStore::new(2), 8, 10)
  inspect(arena.get_max_slots(), content="2")
  // can allocate up to the clamped limit
  inspect(arena.alloc() is None, content="false")
  inspect(arena.alloc() is None, content="false")
  inspect(arena.alloc(), content="None")
}

///|
test "Arena::new_with clamps negative max_slots to zero" {
  let arena = Arena::new_with(MbBump::new(32), MbGenStore::new(4), 8, -5)
  inspect(arena.get_max_slots(), content="0")
  inspect(arena.alloc(), content="None")
}

///|
test "panic Arena::new_with aborts on non-empty bump allocator" {
  let bump = MbBump::new(32)
  bump.alloc(8, 1) |> ignore
  Arena::new_with(bump, MbGenStore::new(4), 8, 4) |> ignore
}

///|
test "panic Arena::reset aborts on generation overflow" {
  let arena = Arena::new(4, 8)
  arena.generation = @int.max_value
  arena.reset()
}

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
test "panic Arena::reset aborts on generation overflow" {
  let arena = Arena::new(4, 8)
  arena.generation = @int.max_value
  arena.reset()
}

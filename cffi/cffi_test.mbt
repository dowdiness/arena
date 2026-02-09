///|
test "Arena[CFFIBump, CGenStore]::alloc returns valid Refs" {
  let arena = new_arena(4, 8)
  let r0 = arena.alloc()
  let r1 = arena.alloc()
  inspect(r0 is None, content="false")
  inspect(r1 is None, content="false")
  inspect(arena.is_valid(r0.unwrap()), content="true")
  inspect(arena.is_valid(r1.unwrap()), content="true")
}

///|
test "Arena[CFFIBump, CGenStore]::is_valid returns false after reset (stale ref detection)" {
  let arena = new_arena(4, 8)
  let r0 = arena.alloc().unwrap()
  inspect(arena.is_valid(r0), content="true")
  arena.reset()
  inspect(arena.is_valid(r0), content="false")
}

///|
test "Arena[CFFIBump, CGenStore]::multiple alloc/reset cycles" {
  let arena = new_arena(4, 8)
  let r0 = arena.alloc().unwrap()
  inspect(arena.get_generation(), content="1")
  arena.reset()
  inspect(arena.get_generation(), content="2")
  let r1 = arena.alloc().unwrap()
  inspect(arena.is_valid(r0), content="false")
  inspect(arena.is_valid(r1), content="true")
  arena.reset()
  inspect(arena.get_generation(), content="3")
  inspect(arena.is_valid(r1), content="false")
}

///|
test "Arena[CFFIBump, CGenStore]::alloc returns None at capacity" {
  let arena = new_arena(2, 8)
  inspect(arena.alloc() is None, content="false")
  inspect(arena.alloc() is None, content="false")
  inspect(arena.alloc(), content="None")
}

///|
test "Arena[CFFIBump, CGenStore]::slot_offset returns correct byte position" {
  let arena = new_arena(4, 16)
  let r0 = arena.alloc().unwrap()
  let r1 = arena.alloc().unwrap()
  inspect(arena.slot_offset(r0), content="Some(0)")
  inspect(arena.slot_offset(r1), content="Some(16)")
}

///|
test "Arena[CFFIBump, CGenStore]::read/write int32 round-trip" {
  let arena = new_arena(4, 8)
  let r = arena.alloc().unwrap()
  inspect(arena.write_int32(r, 0, 42), content="true")
  inspect(arena.read_int32(r, 0), content="Some(42)")
  inspect(arena.write_int32(r, 4, -1), content="true")
  inspect(arena.read_int32(r, 4), content="Some(-1)")
}

///|
test "Arena[CFFIBump, CGenStore]::read/write double round-trip" {
  let arena = new_arena(4, 16)
  let r = arena.alloc().unwrap()
  inspect(arena.write_double(r, 0, 3.14), content="true")
  inspect(arena.read_double(r, 0), content="Some(3.14)")
  inspect(arena.write_double(r, 8, -0.5), content="true")
  inspect(arena.read_double(r, 8), content="Some(-0.5)")
}

///|
test "Arena[CFFIBump, CGenStore]::stale ref write returns false, read returns None" {
  let arena = new_arena(4, 8)
  let r = arena.alloc().unwrap()
  arena.reset()
  inspect(arena.write_int32(r, 0, 42), content="false")
  inspect(arena.read_int32(r, 0), content="None")
  inspect(arena.write_double(r, 0, 1.0), content="false")
  inspect(arena.read_double(r, 0), content="None")
}

///|
test "Arena[CFFIBump, CGenStore]::field_offset bounds checking" {
  let arena = new_arena(4, 8)
  let r = arena.alloc().unwrap()
  // field_offset 8 with int32 (4 bytes) exceeds slot_size 8
  inspect(arena.write_int32(r, 8, 42), content="false")
  inspect(arena.read_int32(r, 8), content="None")
  // field_offset 5 with int32 would read past slot end (5+4=9 > 8)
  inspect(arena.write_int32(r, 5, 42), content="false")
  inspect(arena.read_int32(r, 5), content="None")
  // negative field_offset
  inspect(arena.write_int32(r, -1, 42), content="false")
  inspect(arena.read_int32(r, -1), content="None")
  // double needs 8 bytes, only fits at offset 0 in slot_size=8
  inspect(arena.write_double(r, 0, 1.0), content="true")
  inspect(arena.write_double(r, 1, 1.0), content="false")
  inspect(arena.read_double(r, 1), content="None")
}

///|
test "Arena[CFFIBump, CGenStore]::get_count and get_max_slots" {
  let arena = new_arena(4, 8)
  inspect(arena.get_count(), content="0")
  inspect(arena.get_max_slots(), content="4")
  arena.alloc() |> ignore
  arena.alloc() |> ignore
  inspect(arena.get_count(), content="2")
}

///|
test "Arena[CFFIBump, CGenStore]::works without explicit destroy (auto-finalization)" {
  let arena = new_arena(4, 16)
  let r = arena.alloc().unwrap()
  inspect(arena.write_double(r, 0, 3.14), content="true")
  inspect(arena.read_double(r, 0), content="Some(3.14)")
  inspect(arena.write_int32(r, 8, 42), content="true")
  inspect(arena.read_int32(r, 8), content="Some(42)")
  arena.reset()
  inspect(arena.is_valid(r), content="false")
  let r2 = arena.alloc().unwrap()
  inspect(arena.is_valid(r2), content="true")
  // No destroy() — finalizer frees both CFFIBump and CGenStore native memory
}

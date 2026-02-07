///|
test "MbBump::alloc returns sequential aligned offsets" {
  let bump = MbBump::new(64)
  inspect(bump.alloc(4, 4), content="Some(0)")
  inspect(bump.alloc(4, 4), content="Some(4)")
  inspect(bump.alloc(4, 4), content="Some(8)")
}

///|
test "MbBump::alloc returns None on capacity exhaustion" {
  let bump = MbBump::new(8)
  inspect(bump.alloc(4, 4), content="Some(0)")
  inspect(bump.alloc(4, 4), content="Some(4)")
  inspect(bump.alloc(4, 4), content="None")
}

///|
test "MbBump::reset brings used to 0 and alloc works again" {
  let bump = MbBump::new(8)
  bump.alloc(8, 1) |> ignore
  inspect(bump.used(), content="8")
  bump.reset()
  inspect(bump.used(), content="0")
  inspect(bump.alloc(4, 4), content="Some(0)")
}

///|
test "MbBump::write_int32/read_int32 round-trip" {
  let bump = MbBump::new(16)
  inspect(bump.write_int32(0, 42), content="true")
  inspect(bump.read_int32(0), content="Some(42)")
  inspect(bump.write_int32(4, -1), content="true")
  inspect(bump.read_int32(4), content="Some(-1)")
  inspect(bump.write_int32(8, 0), content="true")
  inspect(bump.read_int32(8), content="Some(0)")
}

///|
test "MbBump::write_double/read_double round-trip" {
  let bump = MbBump::new(24)
  inspect(bump.write_double(0, 3.14), content="true")
  inspect(bump.read_double(0), content="Some(3.14)")
  inspect(bump.write_double(8, -0.0), content="true")
  inspect(bump.read_double(8), content="Some(0)")
  inspect(bump.write_double(16, 1.0e10), content="true")
  inspect(bump.read_double(16), content="Some(10000000000)")
}

///|
test "MbBump::alloc alignment correctness" {
  let bump = MbBump::new(64)
  // Alloc 3 bytes unaligned
  inspect(bump.alloc(3, 1), content="Some(0)")
  // Next alloc with align=8 should skip to offset 8
  inspect(bump.alloc(8, 8), content="Some(8)")
  inspect(bump.used(), content="16")
}

///|
test "MbBump::alloc rejects zero alignment" {
  let bump = MbBump::new(64)
  inspect(bump.alloc(4, 0), content="None")
  inspect(bump.alloc(4, -1), content="None")
  inspect(bump.used(), content="0")
}

///|
test "MbBump::alloc rejects non-positive size" {
  let bump = MbBump::new(64)
  inspect(bump.alloc(0, 4), content="None")
  inspect(bump.alloc(-4, 1), content="None")
  inspect(bump.used(), content="0")
}

///|
test "MbBump::alloc rejects overflowing alignment" {
  let bump = MbBump::new(16)
  bump.alloc(4, 1) |> ignore
  // Large align would overflow in (offset + align - 1), must not return overlapping offset
  inspect(bump.alloc(1, @int.max_value), content="None")
  // Bump state unchanged
  inspect(bump.used(), content="4")
}

///|
test "MbBump::alloc rejects overflowing size" {
  let bump = MbBump::new(16)
  bump.alloc(4, 1) |> ignore
  // @int.max_value + aligned wraps negative, must not succeed
  inspect(bump.alloc(@int.max_value, 1), content="None")
  // Bump state unchanged after rejection
  inspect(bump.used(), content="4")
}

///|
test "MbBump::new clamps negative capacity to zero" {
  let bump = MbBump::new(-1)
  inspect(bump.capacity(), content="0")
  inspect(bump.alloc(1, 1), content="None")
}

///|
test "MbBump::typed accessors reject out-of-bounds offsets" {
  let bump = MbBump::new(4)
  // write_int32 at offset 2 needs bytes 2..5, but capacity is 4
  inspect(bump.write_int32(2, 42), content="false")
  inspect(bump.read_int32(2), content="None")
  // negative offset
  inspect(bump.write_int32(-1, 42), content="false")
  inspect(bump.read_int32(-1), content="None")
  // double needs 8 bytes, only 4 available
  inspect(bump.write_double(0, 1.0), content="false")
  inspect(bump.read_double(0), content="None")
  // valid write_int32 at offset 0
  inspect(bump.write_int32(0, 42), content="true")
  inspect(bump.read_int32(0), content="Some(42)")
}

///|
test "MbBump::capacity" {
  let bump = MbBump::new(256)
  inspect(bump.capacity(), content="256")
}

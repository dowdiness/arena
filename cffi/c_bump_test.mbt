///|
test "CFFIBump::alloc returns sequential aligned offsets" {
  let bump = CFFIBump::new(64)
  inspect(bump.alloc(4, 4), content="Some(0)")
  inspect(bump.alloc(4, 4), content="Some(4)")
  inspect(bump.alloc(4, 4), content="Some(8)")
}

///|
test "CFFIBump::alloc returns None on capacity exhaustion" {
  let bump = CFFIBump::new(8)
  inspect(bump.alloc(4, 4), content="Some(0)")
  inspect(bump.alloc(4, 4), content="Some(4)")
  inspect(bump.alloc(4, 4), content="None")
}

///|
test "CFFIBump::reset brings used to 0 and alloc works again" {
  let bump = CFFIBump::new(8)
  bump.alloc(8, 1) |> ignore
  inspect(bump.used(), content="8")
  bump.reset()
  inspect(bump.used(), content="0")
  inspect(bump.alloc(4, 4), content="Some(0)")
}

///|
test "CFFIBump::write_int32/read_int32 round-trip" {
  let bump = CFFIBump::new(16)
  inspect(bump.write_int32(0, 42), content="true")
  inspect(bump.read_int32(0), content="Some(42)")
  inspect(bump.write_int32(4, -1), content="true")
  inspect(bump.read_int32(4), content="Some(-1)")
  inspect(bump.write_int32(8, 0), content="true")
  inspect(bump.read_int32(8), content="Some(0)")
}

///|
test "CFFIBump::write_double/read_double round-trip" {
  let bump = CFFIBump::new(24)
  inspect(bump.write_double(0, 3.14), content="true")
  inspect(bump.read_double(0), content="Some(3.14)")
  inspect(bump.write_double(8, -0.0), content="true")
  inspect(bump.read_double(8), content="Some(0)")
  inspect(bump.write_double(16, 1.0e10), content="true")
  inspect(bump.read_double(16), content="Some(10000000000)")
}

///|
test "CFFIBump::alloc alignment correctness" {
  let bump = CFFIBump::new(64)
  // Alloc 3 bytes unaligned
  inspect(bump.alloc(3, 1), content="Some(0)")
  // Next alloc with align=8 should skip to offset 8
  inspect(bump.alloc(8, 8), content="Some(8)")
  inspect(bump.used(), content="16")
}

///|
test "CFFIBump::alloc rejects zero alignment" {
  let bump = CFFIBump::new(64)
  inspect(bump.alloc(4, 0), content="None")
  inspect(bump.alloc(4, -1), content="None")
  inspect(bump.used(), content="0")
}

///|
test "CFFIBump::alloc rejects non-positive size" {
  let bump = CFFIBump::new(64)
  inspect(bump.alloc(0, 4), content="None")
  inspect(bump.alloc(-4, 1), content="None")
  inspect(bump.used(), content="0")
}

///|
test "CFFIBump::new clamps negative capacity to zero" {
  let bump = CFFIBump::new(-1)
  inspect(bump.capacity(), content="0")
  inspect(bump.alloc(1, 1), content="None")
}

///|
test "CFFIBump::typed accessors reject out-of-bounds offsets" {
  let bump = CFFIBump::new(4)
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
test "CFFIBump::capacity" {
  let bump = CFFIBump::new(256)
  inspect(bump.capacity(), content="256")
}

///|
test "CFFIBump::destroy is safe against double-free" {
  let bump = CFFIBump::new(16)
  bump.destroy()
  bump.destroy() // second destroy must not crash
}

///|
test "CFFIBump::methods are safe after destroy" {
  let bump = CFFIBump::new(16)
  bump.alloc(4, 4) |> ignore
  bump.destroy()
  inspect(bump.alloc(4, 4), content="None")
  inspect(bump.used(), content="0")
  inspect(bump.write_int32(0, 42), content="false")
  inspect(bump.read_int32(0), content="None")
  inspect(bump.write_double(0, 1.0), content="false")
  inspect(bump.read_double(0), content="None")
}

///|
test "CFFIBump::new zero capacity is safe" {
  let bump = CFFIBump::new(0)
  inspect(bump.capacity(), content="0")
  inspect(bump.alloc(1, 1), content="None")
  inspect(bump.used(), content="0")
}

///|
test "CFFIBump::write_byte/read_byte round-trip" {
  let bump = CFFIBump::new(4)
  inspect(bump.write_byte(0, b'\x42'), content="true")
  inspect(bump.read_byte(0), content="Some(b'\\x42')")
  inspect(bump.write_byte(3, b'\xFF'), content="true")
  inspect(bump.read_byte(3), content="Some(b'\\xFF')")
}

///|
test "CFFIBump::write_byte/read_byte rejects out-of-bounds" {
  let bump = CFFIBump::new(4)
  inspect(bump.write_byte(-1, b'\x00'), content="false")
  inspect(bump.read_byte(-1), content="None")
  inspect(bump.write_byte(4, b'\x00'), content="false")
  inspect(bump.read_byte(4), content="None")
}

///|
test "CFFIBump::byte methods are safe after destroy" {
  let bump = CFFIBump::new(4)
  bump.write_byte(0, b'\x42') |> ignore
  bump.destroy()
  inspect(bump.write_byte(0, b'\x42'), content="false")
  inspect(bump.read_byte(0), content="None")
}

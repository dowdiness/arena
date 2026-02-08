///|
test "MbBump::BumpAllocator contract - allocated range supports typed writes" {
  let bump = MbBump::new(64)
  let offset = bump.alloc(16, 8).unwrap()
  inspect(offset, content="0")
  inspect(bump.write_int32(offset, 42), content="true")
  inspect(bump.read_int32(offset), content="Some(42)")
  inspect(bump.write_double(offset + 8, 3.14), content="true")
  inspect(bump.read_double(offset + 8), content="Some(3.14)")
}

///|
test "MbBump::BumpAllocator contract - used is monotonic until reset" {
  let bump = MbBump::new(64)
  bump.alloc(8, 8) |> ignore
  let used1 = bump.used()
  bump.alloc(8, 8) |> ignore
  let used2 = bump.used()
  inspect(used1 <= used2, content="true")
  bump.reset()
  inspect(bump.used(), content="0")
  inspect(bump.alloc(8, 8), content="Some(0)")
}

///|
test "MbBump::BumpAllocator contract - invalid offsets fail safely" {
  let bump = MbBump::new(8)
  inspect(bump.write_int32(5, 1), content="false")
  inspect(bump.read_int32(5), content="None")
  inspect(bump.write_double(1, 1.0), content="false")
  inspect(bump.read_double(1), content="None")
}

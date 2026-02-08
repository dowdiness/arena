///|
test "F64Arena[CFFIBump, CGenStore]::alloc and get" {
  let arena = @arena.F64Arena::new_with(CFFIBump::new(32), CGenStore::new(4), 4)
  let r = arena.alloc(3.14).unwrap()
  inspect(arena.is_valid(r), content="true")
  inspect(arena.get(r), content="Some(3.14)")
}

///|
test "F64Arena[CFFIBump, CGenStore]::set overwrites value" {
  let arena = @arena.F64Arena::new_with(CFFIBump::new(32), CGenStore::new(4), 4)
  let r = arena.alloc(3.14).unwrap()
  inspect(arena.set(r, 2.718), content="true")
  inspect(arena.get(r), content="Some(2.718)")
}

///|
test "F64Arena[CFFIBump, CGenStore]::stale ref after reset" {
  let arena = @arena.F64Arena::new_with(CFFIBump::new(32), CGenStore::new(4), 4)
  let r = arena.alloc(1.0).unwrap()
  arena.reset()
  inspect(arena.get(r), content="None")
  inspect(arena.set(r, 2.0), content="false")
  inspect(arena.is_valid(r), content="false")
}

///|
test "F64Arena[CFFIBump, CGenStore]::alloc at capacity" {
  let arena = @arena.F64Arena::new_with(CFFIBump::new(16), CGenStore::new(2), 2)
  inspect(arena.alloc(1.0) is None, content="false")
  inspect(arena.alloc(2.0) is None, content="false")
  inspect(arena.alloc(3.0), content="None")
}

///|
test "I32Arena[CFFIBump, CGenStore]::alloc and get" {
  let arena = @arena.I32Arena::new_with(CFFIBump::new(16), CGenStore::new(4), 4)
  let r = arena.alloc(42).unwrap()
  inspect(arena.is_valid(r), content="true")
  inspect(arena.get(r), content="Some(42)")
}

///|
test "I32Arena[CFFIBump, CGenStore]::set overwrites value" {
  let arena = @arena.I32Arena::new_with(CFFIBump::new(16), CGenStore::new(4), 4)
  let r = arena.alloc(42).unwrap()
  inspect(arena.set(r, -1), content="true")
  inspect(arena.get(r), content="Some(-1)")
}

///|
test "I32Arena[CFFIBump, CGenStore]::stale ref after reset" {
  let arena = @arena.I32Arena::new_with(CFFIBump::new(16), CGenStore::new(4), 4)
  let r = arena.alloc(42).unwrap()
  arena.reset()
  inspect(arena.get(r), content="None")
  inspect(arena.set(r, 99), content="false")
  inspect(arena.is_valid(r), content="false")
}

///|
test "AudioArena[CFFIBump, CGenStore]::alloc and get" {
  let arena = @arena.AudioArena::new_with(
    CFFIBump::new(64),
    CGenStore::new(4),
    4,
  )
  let frame = @arena.AudioFrame::new(0.75, -0.25)
  let r = arena.alloc(frame).unwrap()
  inspect(arena.is_valid(r), content="true")
  inspect(arena.get(r), content="Some({left: 0.75, right: -0.25})")
}

///|
test "AudioArena[CFFIBump, CGenStore]::set overwrites frame" {
  let arena = @arena.AudioArena::new_with(
    CFFIBump::new(64),
    CGenStore::new(4),
    4,
  )
  let frame = @arena.AudioFrame::new(0.5, -0.5)
  let r = arena.alloc(frame).unwrap()
  let new_frame = @arena.AudioFrame::new(1.0, -1.0)
  inspect(arena.set(r, new_frame), content="true")
  inspect(arena.get(r), content="Some({left: 1, right: -1})")
}

///|
test "AudioArena[CFFIBump, CGenStore]::stale ref after reset" {
  let arena = @arena.AudioArena::new_with(
    CFFIBump::new(64),
    CGenStore::new(4),
    4,
  )
  let frame = @arena.AudioFrame::new(0.5, -0.5)
  let r = arena.alloc(frame).unwrap()
  arena.reset()
  inspect(arena.get(r), content="None")
  inspect(arena.set(r, frame), content="false")
  inspect(arena.is_valid(r), content="false")
}

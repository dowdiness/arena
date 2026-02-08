///|
test "AudioArena::alloc returns valid TypedRef" {
  let arena = AudioArena::new(4)
  let frame = AudioFrame::new(0.5, -0.5)
  let r = arena.alloc(frame)
  inspect(r is None, content="false")
  inspect(arena.is_valid(r.unwrap()), content="true")
}

///|
test "AudioArena::get returns stored frame" {
  let arena = AudioArena::new(4)
  let frame = AudioFrame::new(0.75, -0.25)
  let r = arena.alloc(frame).unwrap()
  inspect(arena.get(r), content="Some({left: 0.75, right: -0.25})")
}

///|
test "AudioArena::set overwrites frame" {
  let arena = AudioArena::new(4)
  let frame = AudioFrame::new(0.5, -0.5)
  let r = arena.alloc(frame).unwrap()
  let new_frame = AudioFrame::new(1.0, -1.0)
  inspect(arena.set(r, new_frame), content="true")
  inspect(arena.get(r), content="Some({left: 1, right: -1})")
}

///|
test "AudioArena::stale ref after reset" {
  let arena = AudioArena::new(4)
  let frame = AudioFrame::new(0.5, -0.5)
  let r = arena.alloc(frame).unwrap()
  arena.reset()
  inspect(arena.get(r), content="None")
  inspect(arena.set(r, frame), content="false")
  inspect(arena.is_valid(r), content="false")
}

///|
test "AudioArena::alloc at capacity returns None" {
  let arena = AudioArena::new(2)
  let frame = AudioFrame::new(0.5, -0.5)
  inspect(arena.alloc(frame) is None, content="false")
  inspect(arena.alloc(frame) is None, content="false")
  inspect(arena.alloc(frame), content="None")
}

///|
test "AudioArena::multiple alloc/reset cycles" {
  let arena = AudioArena::new(2)
  let f0 = AudioFrame::new(0.1, 0.2)
  let r0 = arena.alloc(f0).unwrap()
  inspect(arena.get(r0), content="Some({left: 0.1, right: 0.2})")
  arena.reset()
  let f1 = AudioFrame::new(0.3, 0.4)
  let r1 = arena.alloc(f1).unwrap()
  inspect(arena.is_valid(r0), content="false")
  inspect(arena.is_valid(r1), content="true")
  inspect(arena.get(r1), content="Some({left: 0.3, right: 0.4})")
  arena.reset()
  inspect(arena.is_valid(r1), content="false")
}

///|
test "AudioArena::verify left and right independently" {
  let arena = AudioArena::new(4)
  let frame = AudioFrame::new(0.123, 0.456)
  let r = arena.alloc(frame).unwrap()
  let got = arena.get(r).unwrap()
  inspect(got.left, content="0.123")
  inspect(got.right, content="0.456")
}

///|
test "I32Arena::alloc returns valid TypedRef" {
  let arena = I32Arena::new(4)
  let r = arena.alloc(42)
  inspect(r is None, content="false")
  inspect(arena.is_valid(r.unwrap()), content="true")
}

///|
test "I32Arena::get returns stored value" {
  let arena = I32Arena::new(4)
  let r = arena.alloc(42).unwrap()
  inspect(arena.get(r), content="Some(42)")
}

///|
test "I32Arena::set overwrites value" {
  let arena = I32Arena::new(4)
  let r = arena.alloc(42).unwrap()
  inspect(arena.set(r, -1), content="true")
  inspect(arena.get(r), content="Some(-1)")
}

///|
test "I32Arena::stale ref after reset" {
  let arena = I32Arena::new(4)
  let r = arena.alloc(42).unwrap()
  arena.reset()
  inspect(arena.get(r), content="None")
  inspect(arena.set(r, 99), content="false")
  inspect(arena.is_valid(r), content="false")
}

///|
test "I32Arena::alloc at capacity returns None" {
  let arena = I32Arena::new(2)
  inspect(arena.alloc(1) is None, content="false")
  inspect(arena.alloc(2) is None, content="false")
  inspect(arena.alloc(3), content="None")
}

///|
test "I32Arena::multiple alloc/reset cycles" {
  let arena = I32Arena::new(2)
  let r0 = arena.alloc(10).unwrap()
  inspect(arena.get(r0), content="Some(10)")
  arena.reset()
  let r1 = arena.alloc(20).unwrap()
  inspect(arena.is_valid(r0), content="false")
  inspect(arena.is_valid(r1), content="true")
  inspect(arena.get(r1), content="Some(20)")
  arena.reset()
  inspect(arena.is_valid(r1), content="false")
}

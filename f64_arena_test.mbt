///|
test "F64Arena::alloc returns valid TypedRef" {
  let arena = F64Arena::new(4)
  let r = arena.alloc(3.14)
  inspect(r is None, content="false")
  inspect(arena.is_valid(r.unwrap()), content="true")
}

///|
test "F64Arena::get returns stored value" {
  let arena = F64Arena::new(4)
  let r = arena.alloc(3.14).unwrap()
  inspect(arena.get(r), content="Some(3.14)")
}

///|
test "F64Arena::set overwrites value" {
  let arena = F64Arena::new(4)
  let r = arena.alloc(3.14).unwrap()
  inspect(arena.set(r, 2.718), content="true")
  inspect(arena.get(r), content="Some(2.718)")
}

///|
test "F64Arena::stale ref after reset" {
  let arena = F64Arena::new(4)
  let r = arena.alloc(1.0).unwrap()
  arena.reset()
  inspect(arena.get(r), content="None")
  inspect(arena.set(r, 2.0), content="false")
  inspect(arena.is_valid(r), content="false")
}

///|
test "F64Arena::alloc at capacity returns None" {
  let arena = F64Arena::new(2)
  inspect(arena.alloc(1.0) is None, content="false")
  inspect(arena.alloc(2.0) is None, content="false")
  inspect(arena.alloc(3.0), content="None")
}

///|
test "F64Arena::multiple alloc/reset cycles" {
  let arena = F64Arena::new(2)
  let r0 = arena.alloc(1.0).unwrap()
  inspect(arena.get(r0), content="Some(1)")
  arena.reset()
  let r1 = arena.alloc(2.0).unwrap()
  inspect(arena.is_valid(r0), content="false")
  inspect(arena.is_valid(r1), content="true")
  inspect(arena.get(r1), content="Some(2)")
  arena.reset()
  inspect(arena.is_valid(r1), content="false")
}

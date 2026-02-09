///|
test "CGenStore::new initializes all slots to 0" {
  let store = CGenStore::new(4)
  inspect(store.get(0), content="0")
  inspect(store.get(1), content="0")
  inspect(store.get(2), content="0")
  inspect(store.get(3), content="0")
}

///|
test "CGenStore::get/set round-trip" {
  let store = CGenStore::new(4)
  store.set(0, 42)
  inspect(store.get(0), content="42")
  store.set(2, 99)
  inspect(store.get(2), content="99")
}

///|
test "CGenStore::independent slot updates" {
  let store = CGenStore::new(4)
  store.set(0, 10)
  store.set(1, 20)
  store.set(2, 30)
  inspect(store.get(0), content="10")
  inspect(store.get(1), content="20")
  inspect(store.get(2), content="30")
  inspect(store.get(3), content="0")
}

///|
test "CGenStore::new clamps negative slot count to zero" {
  let store = CGenStore::new(-1)
  inspect(store.length(), content="0")
}

///|
test "CGenStore::length" {
  let store = CGenStore::new(8)
  inspect(store.length(), content="8")
}

///|
test "CGenStore::destroy is safe against double-free" {
  let store = CGenStore::new(4)
  store.destroy()
  store.destroy() // second destroy must not crash
}

///|
test "CGenStore::new zero length is safe" {
  let store = CGenStore::new(0)
  inspect(store.length(), content="0")
}

///|
test "panic CGenStore::set aborts on negative index" {
  let store = CGenStore::new(4)
  store.set(-1, 42)
}

///|
test "panic CGenStore::set aborts on out-of-bounds index" {
  let store = CGenStore::new(4)
  store.set(4, 42)
}

///|
test "panic CGenStore::get aborts on negative index" {
  let store = CGenStore::new(4)
  store.get(-1) |> ignore
}

///|
test "panic CGenStore::get aborts on out-of-bounds index" {
  let store = CGenStore::new(4)
  store.get(4) |> ignore
}

///|
test "CGenStore::works without explicit destroy (auto-finalization)" {
  let store = CGenStore::new(4)
  store.set(0, 42)
  store.set(1, 99)
  inspect(store.get(0), content="42")
  inspect(store.get(1), content="99")
  // No destroy() — finalizer frees native memory when RC drops to 0
}

///|
test "CGenStore::destroy then finalizer (no double-free)" {
  let store = CGenStore::new(4)
  store.set(0, 42)
  inspect(store.get(0), content="42")
  store.destroy()
  // After destroy, data is NULL; finalizer will see NULL and skip free
  store.destroy() // second destroy is also safe
}

///|
test "MbGenStore::new initializes all slots to 0" {
  let store = MbGenStore::new(4)
  inspect(store.get(0), content="0")
  inspect(store.get(1), content="0")
  inspect(store.get(2), content="0")
  inspect(store.get(3), content="0")
}

///|
test "MbGenStore::get/set round-trip" {
  let store = MbGenStore::new(4)
  store.set(0, 42)
  inspect(store.get(0), content="42")
  store.set(2, 99)
  inspect(store.get(2), content="99")
}

///|
test "MbGenStore::independent slot updates" {
  let store = MbGenStore::new(4)
  store.set(0, 10)
  store.set(1, 20)
  store.set(2, 30)
  inspect(store.get(0), content="10")
  inspect(store.get(1), content="20")
  inspect(store.get(2), content="30")
  inspect(store.get(3), content="0")
}

///|
test "MbGenStore::new clamps negative slot count to zero" {
  let store = MbGenStore::new(-1)
  inspect(store.length(), content="0")
}

///|
test "MbGenStore::length" {
  let store = MbGenStore::new(8)
  inspect(store.length(), content="8")
}

///|
test "MbGenStore::get throughput" (b : @bench.T) {
  let gs = MbGenStore::new(1024)
  let mut i = 0
  while i < 1024 {
    gs.set(i, i + 1)
    i += 1
  }
  b.bench(fn() {
    let mut i = 0
    while i < 1000 {
      b.keep(gs.get(i % 1024))
      i += 1
    }
  })
}

///|
test "MbGenStore::set throughput" (b : @bench.T) {
  let gs = MbGenStore::new(1024)
  b.bench(fn() {
    let mut i = 0
    while i < 1000 {
      gs.set(i % 1024, i)
      i += 1
    }
  })
}

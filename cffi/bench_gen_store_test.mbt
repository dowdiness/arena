///|
test "CGenStore::get throughput" (b : @bench.T) {
  let gs = CGenStore::new(1024)
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
test "CGenStore::set throughput" (b : @bench.T) {
  let gs = CGenStore::new(1024)
  b.bench(fn() {
    let mut i = 0
    while i < 1000 {
      gs.set(i % 1024, i)
      i += 1
    }
  })
}

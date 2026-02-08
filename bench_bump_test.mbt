///|
test "MbBump::alloc throughput (8-byte, align=1)" (b : @bench.T) {
  let bump = MbBump::new(65536)
  b.bench(fn() {
    bump.reset()
    let mut i = 0
    while i < 1000 {
      b.keep(bump.alloc(8, 1))
      i += 1
    }
  })
}

///|
test "MbBump::alloc throughput (8-byte, align=8)" (b : @bench.T) {
  let bump = MbBump::new(65536)
  b.bench(fn() {
    bump.reset()
    let mut i = 0
    while i < 1000 {
      b.keep(bump.alloc(8, 8))
      i += 1
    }
  })
}

///|
test "MbBump::write_int32 + read_int32 throughput" (b : @bench.T) {
  let bump = MbBump::new(8192)
  b.bench(fn() {
    let mut i = 0
    while i < 1000 {
      let offset = i % 1024 * 4 // (i % 1024) * 4
      bump.write_int32(offset, i) |> ignore
      b.keep(bump.read_int32(offset))
      i += 1
    }
  })
}

///|
test "MbBump::write_double + read_double throughput" (b : @bench.T) {
  let bump = MbBump::new(8192)
  b.bench(fn() {
    let mut i = 0
    while i < 1000 {
      let offset = i % 1024 * 8 // (i % 1024) * 8
      bump.write_double(offset, 3.14) |> ignore
      b.keep(bump.read_double(offset))
      i += 1
    }
  })
}

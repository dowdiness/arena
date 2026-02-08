///|
fn prefill_arena(
  arena : @arena.Arena[CFFIBump, CGenStore],
  slot_count : Int,
) -> Unit {
  let mut i = 0
  while i < slot_count {
    arena.alloc() |> ignore
    i += 1
  }
}

///|
fn measure_reset_only_avg_us(
  arena : @arena.Arena[CFFIBump, CGenStore],
  fill_count : Int,
  samples : Int,
) -> Double {
  if samples <= 0 {
    return 0.0
  }
  prefill_arena(arena, fill_count)
  let mut total_us = 0.0
  let mut i = 0
  while i < samples {
    let started = @bench.monotonic_clock_start()
    arena.reset()
    total_us += @bench.monotonic_clock_end(started)
    prefill_arena(arena, fill_count)
    i += 1
  }
  total_us / samples.to_double()
}

///|
test "Arena[CFFIBump,CGenStore] alloc 1000 slots" (b : @bench.T) {
  let arena = new_arena(1000, 16)
  b.bench(fn() {
    arena.reset()
    let mut i = 0
    while i < 1000 {
      b.keep(arena.alloc())
      i += 1
    }
  })
}

///|
test "Arena[CFFIBump,CGenStore] reset baseline (empty arena)" (b : @bench.T) {
  let arena = new_arena(10000, 8)
  b.bench(fn() { arena.reset() })
}

///|
test "Arena[CFFIBump,CGenStore] reset-only complexity sweep (monotonic clock)" (
  b : @bench.T,
) {
  let reset_0 = measure_reset_only_avg_us(new_arena(0, 8), 0, 50000)
  let reset_100 = measure_reset_only_avg_us(new_arena(100, 8), 100, 20000)
  let reset_1000 = measure_reset_only_avg_us(new_arena(1000, 8), 1000, 5000)
  let reset_10000 = measure_reset_only_avg_us(new_arena(10000, 8), 10000, 500)
  println(
    "reset-only avg us (CFFIBump): N=0 \{reset_0}, N=100 \{reset_100}, N=1000 \{reset_1000}, N=10000 \{reset_10000}",
  )
  b.keep(reset_0 + reset_100 + reset_1000 + reset_10000)
}

///|
test "Arena[CFFIBump,CGenStore] reset+refill cycle (100 allocs)" (b : @bench.T) {
  let arena = new_arena(100, 8)
  prefill_arena(arena, 100)
  b.bench(fn() {
    arena.reset()
    prefill_arena(arena, 100)
  })
}

///|
test "Arena[CFFIBump,CGenStore] reset+refill cycle (10000 allocs)" (
  b : @bench.T,
) {
  let arena = new_arena(10000, 8)
  prefill_arena(arena, 10000)
  b.bench(fn() {
    arena.reset()
    prefill_arena(arena, 10000)
  })
}

///|
test "Arena[CFFIBump,CGenStore] write_double + read_double" (b : @bench.T) {
  let arena = new_arena(1024, 16)
  let refs : Array[@arena.Ref] = []
  let mut i = 0
  while i < 1024 {
    match arena.alloc() {
      Some(r) => refs.push(r)
      None => break
    }
    i += 1
  }
  b.bench(fn() {
    let mut i = 0
    while i < 1000 {
      let r = refs[i % refs.length()]
      arena.write_double(r, 0, 3.14) |> ignore
      b.keep(arena.read_double(r, 0))
      i += 1
    }
  })
}

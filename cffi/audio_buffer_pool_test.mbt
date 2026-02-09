///|
test "AudioBufferPool[CFFIBump, CGenStore]::alloc and read_sample round-trip" {
  // 64 frames * 2 channels * 8 bytes = 1024 bytes per buffer
  let pool = @arena.AudioBufferPool::new_with(
    CFFIBump::new(4096),
    CGenStore::new(4),
    64,
    2,
    4,
  )
  let bref = pool.alloc().unwrap()
  inspect(pool.is_valid(bref), content="true")
  inspect(pool.write_sample(bref, 0, 0, 0.5), content="true")
  inspect(pool.write_sample(bref, 0, 1, -0.5), content="true")
  inspect(pool.read_sample(bref, 0, 0), content="Some(0.5)")
  inspect(pool.read_sample(bref, 0, 1), content="Some(-0.5)")
}

///|
test "AudioBufferPool[CFFIBump, CGenStore]::write_sample overwrites value" {
  let pool = @arena.AudioBufferPool::new_with(
    CFFIBump::new(4096),
    CGenStore::new(4),
    64,
    2,
    4,
  )
  let bref = pool.alloc().unwrap()
  pool.write_sample(bref, 0, 0, 0.5) |> ignore
  inspect(pool.write_sample(bref, 0, 0, 0.75), content="true")
  inspect(pool.read_sample(bref, 0, 0), content="Some(0.75)")
}

///|
test "AudioBufferPool[CFFIBump, CGenStore]::stale ref after reset" {
  let pool = @arena.AudioBufferPool::new_with(
    CFFIBump::new(4096),
    CGenStore::new(4),
    64,
    2,
    4,
  )
  let bref = pool.alloc().unwrap()
  pool.write_sample(bref, 0, 0, 0.5) |> ignore
  pool.reset()
  inspect(pool.write_sample(bref, 0, 0, 1.0), content="false")
  inspect(pool.read_sample(bref, 0, 0), content="None")
  inspect(pool.is_valid(bref), content="false")
}

///|
test "AudioBufferPool[CFFIBump, CGenStore]::alloc at capacity" {
  let pool = @arena.AudioBufferPool::new_with(
    CFFIBump::new(2048),
    CGenStore::new(2),
    64,
    2,
    2,
  )
  inspect(pool.alloc() is None, content="false")
  inspect(pool.alloc() is None, content="false")
  inspect(pool.alloc(), content="None")
}

///|
test "AudioBufferPool[CFFIBump, CGenStore]::multi-buffer independence" {
  let pool = @arena.AudioBufferPool::new_with(
    CFFIBump::new(4096),
    CGenStore::new(4),
    64,
    2,
    4,
  )
  let a = pool.alloc().unwrap()
  let b = pool.alloc().unwrap()
  pool.write_sample(a, 0, 0, 0.5) |> ignore
  pool.write_sample(b, 0, 0, -0.5) |> ignore
  inspect(pool.read_sample(a, 0, 0), content="Some(0.5)")
  inspect(pool.read_sample(b, 0, 0), content="Some(-0.5)")
}

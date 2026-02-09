///|
test "AudioBufferPool::alloc returns valid BufferRef" {
  let pool = AudioBufferPool::new(256, 2, 4)
  let bref = pool.alloc()
  inspect(bref is None, content="false")
  inspect(pool.is_valid(bref.unwrap()), content="true")
}

///|
test "AudioBufferPool::write_sample/read_sample round-trip (stereo)" {
  let pool = AudioBufferPool::new(256, 2, 4)
  let bref = pool.alloc().unwrap()
  inspect(pool.write_sample(bref, 0, 0, 0.5), content="true")
  inspect(pool.write_sample(bref, 0, 1, -0.5), content="true")
  inspect(pool.write_sample(bref, 255, 0, 1.0), content="true")
  inspect(pool.write_sample(bref, 255, 1, -1.0), content="true")
  inspect(pool.read_sample(bref, 0, 0), content="Some(0.5)")
  inspect(pool.read_sample(bref, 0, 1), content="Some(-0.5)")
  inspect(pool.read_sample(bref, 255, 0), content="Some(1)")
  inspect(pool.read_sample(bref, 255, 1), content="Some(-1)")
}

///|
test "AudioBufferPool::write_sample/read_sample round-trip (mono)" {
  let pool = AudioBufferPool::new(128, 1, 2)
  let bref = pool.alloc().unwrap()
  inspect(pool.write_sample(bref, 0, 0, 0.75), content="true")
  inspect(pool.write_sample(bref, 127, 0, -0.25), content="true")
  inspect(pool.read_sample(bref, 0, 0), content="Some(0.75)")
  inspect(pool.read_sample(bref, 127, 0), content="Some(-0.25)")
}

///|
test "AudioBufferPool::out-of-bounds frame index rejected" {
  let pool = AudioBufferPool::new(64, 2, 2)
  let bref = pool.alloc().unwrap()
  inspect(pool.write_sample(bref, -1, 0, 1.0), content="false")
  inspect(pool.write_sample(bref, 64, 0, 1.0), content="false")
  inspect(pool.read_sample(bref, -1, 0), content="None")
  inspect(pool.read_sample(bref, 64, 0), content="None")
}

///|
test "AudioBufferPool::out-of-bounds channel index rejected" {
  let pool = AudioBufferPool::new(64, 2, 2)
  let bref = pool.alloc().unwrap()
  inspect(pool.write_sample(bref, 0, -1, 1.0), content="false")
  inspect(pool.write_sample(bref, 0, 2, 1.0), content="false")
  inspect(pool.read_sample(bref, 0, -1), content="None")
  inspect(pool.read_sample(bref, 0, 2), content="None")
}

///|
test "AudioBufferPool::stale BufferRef after reset" {
  let pool = AudioBufferPool::new(64, 2, 2)
  let bref = pool.alloc().unwrap()
  pool.write_sample(bref, 0, 0, 0.5) |> ignore
  pool.reset()
  inspect(pool.write_sample(bref, 0, 0, 1.0), content="false")
  inspect(pool.read_sample(bref, 0, 0), content="None")
  inspect(pool.is_valid(bref), content="false")
}

///|
test "AudioBufferPool::alloc at capacity returns None" {
  let pool = AudioBufferPool::new(64, 2, 2)
  inspect(pool.alloc() is None, content="false")
  inspect(pool.alloc() is None, content="false")
  inspect(pool.alloc(), content="None")
}

///|
test "AudioBufferPool::multiple alloc/reset cycles" {
  let pool = AudioBufferPool::new(64, 2, 2)
  let r0 = pool.alloc().unwrap()
  pool.write_sample(r0, 0, 0, 0.1) |> ignore
  inspect(pool.read_sample(r0, 0, 0), content="Some(0.1)")
  pool.reset()
  let r1 = pool.alloc().unwrap()
  inspect(pool.is_valid(r0), content="false")
  inspect(pool.is_valid(r1), content="true")
  pool.write_sample(r1, 0, 0, 0.2) |> ignore
  inspect(pool.read_sample(r1, 0, 0), content="Some(0.2)")
  pool.reset()
  inspect(pool.is_valid(r1), content="false")
}

///|
test "AudioBufferPool::multi-buffer independence" {
  let pool = AudioBufferPool::new(64, 2, 4)
  let a = pool.alloc().unwrap()
  let b = pool.alloc().unwrap()
  pool.write_sample(a, 0, 0, 0.5) |> ignore
  pool.write_sample(b, 0, 0, -0.5) |> ignore
  inspect(pool.read_sample(a, 0, 0), content="Some(0.5)")
  inspect(pool.read_sample(b, 0, 0), content="Some(-0.5)")
}

///|
test "AudioBufferPool::per-callback lifecycle pattern" {
  let pool = AudioBufferPool::new(128, 2, 2)
  // Callback 1: reset → alloc → write → read
  pool.reset()
  let buf = pool.alloc().unwrap()
  pool.write_sample(buf, 0, 0, 0.75) |> ignore
  pool.write_sample(buf, 0, 1, -0.75) |> ignore
  inspect(pool.read_sample(buf, 0, 0), content="Some(0.75)")
  inspect(pool.read_sample(buf, 0, 1), content="Some(-0.75)")
  // Callback 2: reset → alloc → write → read
  pool.reset()
  let buf2 = pool.alloc().unwrap()
  pool.write_sample(buf2, 0, 0, 1.0) |> ignore
  inspect(pool.read_sample(buf2, 0, 0), content="Some(1)")
  // Old ref is stale
  inspect(pool.is_valid(buf), content="false")
}

///|
test "AudioBufferPool::getters" {
  let pool = AudioBufferPool::new(256, 2, 4)
  inspect(pool.get_frames_per_buffer(), content="256")
  inspect(pool.get_channels(), content="2")
}

///|
test "AudioBufferPool::overflow-safe constructor degrades to zero" {
  // frames_per_buffer * channels overflows
  let pool = AudioBufferPool::new(@int.max_value, 2, 1)
  inspect(pool.get_frames_per_buffer(), content="0")
  inspect(pool.get_channels(), content="0")
  inspect(pool.alloc(), content="None")
}

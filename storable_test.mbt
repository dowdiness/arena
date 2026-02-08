///|
test "Storable[Double]::round-trip" {
  let buf = FixedArray::make(8, b'\x00')
  Storable::write_bytes(3.14, buf, 0)
  let v : Double = Storable::read_bytes(buf, 0)
  inspect(v, content="3.14")
}

///|
test "Storable[Double]::negative value round-trip" {
  let buf = FixedArray::make(8, b'\x00')
  Storable::write_bytes(-0.5, buf, 0)
  let v : Double = Storable::read_bytes(buf, 0)
  inspect(v, content="-0.5")
}

///|
test "Storable[Int]::round-trip" {
  let buf = FixedArray::make(4, b'\x00')
  Storable::write_bytes(42, buf, 0)
  let v : Int = Storable::read_bytes(buf, 0)
  inspect(v, content="42")
}

///|
test "Storable[Int]::negative value round-trip" {
  let buf = FixedArray::make(4, b'\x00')
  Storable::write_bytes(-1, buf, 0)
  let v : Int = Storable::read_bytes(buf, 0)
  inspect(v, content="-1")
}

///|
test "Storable[AudioFrame]::round-trip" {
  let buf = FixedArray::make(16, b'\x00')
  let frame = AudioFrame::new(0.75, -0.25)
  Storable::write_bytes(frame, buf, 0)
  let v : AudioFrame = Storable::read_bytes(buf, 0)
  inspect(v, content="{left: 0.75, right: -0.25}")
}

///|
test "Storable[AudioFrame]::zero frame round-trip" {
  let buf = FixedArray::make(16, b'\x00')
  let frame = AudioFrame::new(0.0, 0.0)
  Storable::write_bytes(frame, buf, 0)
  let v : AudioFrame = Storable::read_bytes(buf, 0)
  inspect(v, content="{left: 0, right: 0}")
}

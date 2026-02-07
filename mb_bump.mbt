///|
pub struct MbBump {
  data : FixedArray[Byte]
  mut offset : Int
}

///|
pub fn MbBump::new(capacity : Int) -> MbBump {
  let cap = if capacity < 0 { 0 } else { capacity }
  { data: FixedArray::make(cap, b'\x00'), offset: 0 }
}

///|
pub fn MbBump::alloc(self : MbBump, size : Int, align : Int) -> Int? {
  if size <= 0 || align <= 0 {
    return None
  }
  let remainder = self.offset % align
  let padding = if remainder == 0 { 0 } else { align - remainder }
  let space = self.data.length() - self.offset
  if padding > space {
    return None
  }
  let aligned = self.offset + padding
  let remaining = self.data.length() - aligned
  if size > remaining {
    None
  } else {
    self.offset = aligned + size
    Some(aligned)
  }
}

///|
pub fn MbBump::reset(self : MbBump) -> Unit {
  self.offset = 0
}

///|
pub fn MbBump::capacity(self : MbBump) -> Int {
  self.data.length()
}

///|
pub fn MbBump::used(self : MbBump) -> Int {
  self.offset
}

///|
pub fn MbBump::write_int32(self : MbBump, offset : Int, val : Int) -> Bool {
  if offset < 0 || offset > self.data.length() - 4 {
    return false
  }
  FixedArray::unsafe_write_uint32_le(
    self.data,
    offset,
    val.reinterpret_as_uint(),
  )
  true
}

///|
pub fn MbBump::read_int32(self : MbBump, offset : Int) -> Int? {
  if offset < 0 || offset > self.data.length() - 4 {
    return None
  }
  let b0 = self.data.unsafe_get(offset).to_uint()
  let b1 = self.data.unsafe_get(offset + 1).to_uint()
  let b2 = self.data.unsafe_get(offset + 2).to_uint()
  let b3 = self.data.unsafe_get(offset + 3).to_uint()
  Some((b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)).reinterpret_as_int())
}

///|
pub fn MbBump::write_double(self : MbBump, offset : Int, val : Double) -> Bool {
  if offset < 0 || offset > self.data.length() - 8 {
    return false
  }
  let bits = val.reinterpret_as_int64().reinterpret_as_uint64()
  FixedArray::unsafe_write_uint64_le(self.data, offset, bits)
  true
}

///|
pub fn MbBump::read_double(self : MbBump, offset : Int) -> Double? {
  if offset < 0 || offset > self.data.length() - 8 {
    return None
  }
  let b0 = self.data.unsafe_get(offset).to_uint64()
  let b1 = self.data.unsafe_get(offset + 1).to_uint64()
  let b2 = self.data.unsafe_get(offset + 2).to_uint64()
  let b3 = self.data.unsafe_get(offset + 3).to_uint64()
  let b4 = self.data.unsafe_get(offset + 4).to_uint64()
  let b5 = self.data.unsafe_get(offset + 5).to_uint64()
  let b6 = self.data.unsafe_get(offset + 6).to_uint64()
  let b7 = self.data.unsafe_get(offset + 7).to_uint64()
  let bits = b0 |
    (b1 << 8) |
    (b2 << 16) |
    (b3 << 24) |
    (b4 << 32) |
    (b5 << 40) |
    (b6 << 48) |
    (b7 << 56)
  Some(bits.reinterpret_as_int64().reinterpret_as_double())
}

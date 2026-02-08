///|
pub(open) trait Storable {
  byte_size() -> Int
  write_bytes(Self, FixedArray[Byte], offset : Int) -> Unit
  read_bytes(FixedArray[Byte], offset : Int) -> Self
}

///|
pub impl Storable for Double with byte_size() {
  8
}

///|
pub impl Storable for Double with write_bytes(self, buf, offset) {
  let bits = self.reinterpret_as_int64().reinterpret_as_uint64()
  FixedArray::unsafe_write_uint64_le(buf, offset, bits)
}

///|
pub impl Storable for Double with read_bytes(buf, offset) {
  let b0 = buf.unsafe_get(offset).to_uint64()
  let b1 = buf.unsafe_get(offset + 1).to_uint64()
  let b2 = buf.unsafe_get(offset + 2).to_uint64()
  let b3 = buf.unsafe_get(offset + 3).to_uint64()
  let b4 = buf.unsafe_get(offset + 4).to_uint64()
  let b5 = buf.unsafe_get(offset + 5).to_uint64()
  let b6 = buf.unsafe_get(offset + 6).to_uint64()
  let b7 = buf.unsafe_get(offset + 7).to_uint64()
  let bits = b0 |
    (b1 << 8) |
    (b2 << 16) |
    (b3 << 24) |
    (b4 << 32) |
    (b5 << 40) |
    (b6 << 48) |
    (b7 << 56)
  bits.reinterpret_as_int64().reinterpret_as_double()
}

///|
pub impl Storable for Int with byte_size() {
  4
}

///|
pub impl Storable for Int with write_bytes(self, buf, offset) {
  FixedArray::unsafe_write_uint32_le(buf, offset, self.reinterpret_as_uint())
}

///|
pub impl Storable for Int with read_bytes(buf, offset) {
  let b0 = buf.unsafe_get(offset).to_uint()
  let b1 = buf.unsafe_get(offset + 1).to_uint()
  let b2 = buf.unsafe_get(offset + 2).to_uint()
  let b3 = buf.unsafe_get(offset + 3).to_uint()
  (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)).reinterpret_as_int()
}

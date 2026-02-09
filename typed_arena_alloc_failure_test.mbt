///|
struct WriteFailBump {
  capacity_ : Int
  mut offset_ : Int
}

///|
fn WriteFailBump::new(capacity : Int) -> WriteFailBump {
  let cap = if capacity < 0 { 0 } else { capacity }
  { capacity_: cap, offset_: 0 }
}

///|
impl BumpAllocator for WriteFailBump with alloc(self, size, align) {
  if size <= 0 || align <= 0 {
    return None
  }
  let remainder = self.offset_ % align
  let padding = if remainder == 0 { 0 } else { align - remainder }
  let space = self.capacity_ - self.offset_
  if padding > space {
    return None
  }
  let aligned = self.offset_ + padding
  let remaining = self.capacity_ - aligned
  if size > remaining {
    None
  } else {
    self.offset_ = aligned + size
    Some(aligned)
  }
}

///|
impl BumpAllocator for WriteFailBump with reset(self) {
  self.offset_ = 0
}

///|
impl BumpAllocator for WriteFailBump with capacity(self) {
  self.capacity_
}

///|
impl BumpAllocator for WriteFailBump with used(self) {
  self.offset_
}

///|
impl BumpAllocator for WriteFailBump with write_int32(self, offset, val) {
  ignore(self)
  ignore(offset)
  ignore(val)
  false
}

///|
impl BumpAllocator for WriteFailBump with read_int32(self, offset) {
  ignore(self)
  ignore(offset)
  None
}

///|
impl BumpAllocator for WriteFailBump with write_double(self, offset, val) {
  ignore(self)
  ignore(offset)
  ignore(val)
  false
}

///|
impl BumpAllocator for WriteFailBump with read_double(self, offset) {
  ignore(self)
  ignore(offset)
  None
}

///|
impl BumpAllocator for WriteFailBump with write_byte(self, offset, val) {
  ignore(self)
  ignore(offset)
  ignore(val)
  false
}

///|
impl BumpAllocator for WriteFailBump with read_byte(self, offset) {
  ignore(self)
  ignore(offset)
  None
}

///|
test "panic F64Arena::alloc aborts on backend contract violation" {
  let arena = F64Arena::new_with(WriteFailBump::new(64), MbGenStore::new(4), 4)
  arena.alloc(3.14) |> ignore
}

///|
test "panic I32Arena::alloc aborts on backend contract violation" {
  let arena = I32Arena::new_with(WriteFailBump::new(64), MbGenStore::new(4), 4)
  arena.alloc(42) |> ignore
}

///|
test "panic AudioArena::alloc aborts on backend contract violation" {
  let arena = AudioArena::new_with(
    WriteFailBump::new(64),
    MbGenStore::new(4),
    4,
  )
  arena.alloc(AudioFrame::new(0.5, -0.5)) |> ignore
}

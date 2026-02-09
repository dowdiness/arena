///|
#external
priv type BumpPtr

///|
extern "C" fn bump_create(capacity : Int) -> BumpPtr = "bump_create"

///|
extern "C" fn bump_is_null(ptr : BumpPtr) -> Int = "bump_is_null"

///|
extern "C" fn bump_destroy(ptr : BumpPtr) = "bump_destroy"

///|
#borrow(ptr)
extern "C" fn bump_alloc_(ptr : BumpPtr, size : Int, align : Int) -> Int = "bump_alloc"

///|
#borrow(ptr)
extern "C" fn bump_reset_(ptr : BumpPtr) = "bump_reset"

///|
#borrow(ptr)
extern "C" fn bump_used_(ptr : BumpPtr) -> Int = "bump_used"

///|
#borrow(ptr)
extern "C" fn bump_write_i32_(ptr : BumpPtr, offset : Int, val : Int) = "bump_write_i32"

///|
#borrow(ptr)
extern "C" fn bump_read_i32_(ptr : BumpPtr, offset : Int) -> Int = "bump_read_i32"

///|
#borrow(ptr)
extern "C" fn bump_write_f64_(ptr : BumpPtr, offset : Int, val : Double) = "bump_write_f64"

///|
#borrow(ptr)
extern "C" fn bump_read_f64_(ptr : BumpPtr, offset : Int) -> Double = "bump_read_f64"

///|
#borrow(ptr)
extern "C" fn bump_write_byte_(ptr : BumpPtr, offset : Int, val : Int) -> Unit = "bump_write_byte"

///|
#borrow(ptr)
extern "C" fn bump_read_byte_(ptr : BumpPtr, offset : Int) -> Int = "bump_read_byte"

///|
pub struct CFFIBump {
  priv ptr : BumpPtr
  priv capacity_ : Int
  priv mut destroyed : Bool
}

///|
pub fn CFFIBump::new(capacity : Int) -> CFFIBump {
  let cap = if capacity < 0 { 0 } else { capacity }
  let ptr = bump_create(cap)
  if bump_is_null(ptr) != 0 {
    abort("CFFIBump::new: native allocation failed")
  }
  { ptr, capacity_: cap, destroyed: false }
}

///|
pub fn CFFIBump::destroy(self : CFFIBump) -> Unit {
  if self.destroyed {
    return
  }
  bump_destroy(self.ptr)
  self.destroyed = true
}

///|
pub impl @arena.BumpAllocator for CFFIBump with alloc(self, size, align) {
  if self.destroyed || size <= 0 || align <= 0 {
    return None
  }
  let result = bump_alloc_(self.ptr, size, align)
  if result < 0 {
    None
  } else {
    Some(result)
  }
}

///|
pub impl @arena.BumpAllocator for CFFIBump with reset(self) {
  if self.destroyed {
    return
  }
  bump_reset_(self.ptr)
}

///|
pub impl @arena.BumpAllocator for CFFIBump with capacity(self) {
  self.capacity_
}

///|
pub impl @arena.BumpAllocator for CFFIBump with used(self) {
  if self.destroyed {
    return 0
  }
  bump_used_(self.ptr)
}

///|
pub impl @arena.BumpAllocator for CFFIBump with write_int32(self, offset, val) {
  if self.destroyed || offset < 0 || offset > self.capacity_ - 4 {
    return false
  }
  bump_write_i32_(self.ptr, offset, val)
  true
}

///|
pub impl @arena.BumpAllocator for CFFIBump with read_int32(self, offset) {
  if self.destroyed || offset < 0 || offset > self.capacity_ - 4 {
    return None
  }
  Some(bump_read_i32_(self.ptr, offset))
}

///|
pub impl @arena.BumpAllocator for CFFIBump with write_double(self, offset, val) {
  if self.destroyed || offset < 0 || offset > self.capacity_ - 8 {
    return false
  }
  bump_write_f64_(self.ptr, offset, val)
  true
}

///|
pub impl @arena.BumpAllocator for CFFIBump with read_double(self, offset) {
  if self.destroyed || offset < 0 || offset > self.capacity_ - 8 {
    return None
  }
  Some(bump_read_f64_(self.ptr, offset))
}

///|
pub impl @arena.BumpAllocator for CFFIBump with write_byte(self, offset, val) {
  if self.destroyed || offset < 0 || offset >= self.capacity_ {
    return false
  }
  bump_write_byte_(self.ptr, offset, val.to_int())
  true
}

///|
pub impl @arena.BumpAllocator for CFFIBump with read_byte(self, offset) {
  if self.destroyed || offset < 0 || offset >= self.capacity_ {
    return None
  }
  Some(bump_read_byte_(self.ptr, offset).to_byte())
}

///|
#external
priv type GenPtr

///|
extern "C" fn gen_create(length : Int) -> GenPtr = "gen_create"

///|
extern "C" fn gen_is_null(ptr : GenPtr) -> Int = "gen_is_null"

///|
extern "C" fn gen_destroy(ptr : GenPtr) = "gen_destroy"

///|
#borrow(ptr)
extern "C" fn gen_get_(ptr : GenPtr, index : Int) -> Int = "gen_get"

///|
#borrow(ptr)
extern "C" fn gen_set_(ptr : GenPtr, index : Int, val : Int) = "gen_set"

///|
pub struct CGenStore {
  priv ptr : GenPtr
  priv length_ : Int
  priv mut destroyed : Bool
}

///|
pub fn CGenStore::new(length : Int) -> CGenStore {
  let len = if length < 0 { 0 } else { length }
  let ptr = gen_create(len)
  if gen_is_null(ptr) != 0 {
    abort("CGenStore::new: native allocation failed")
  }
  { ptr, length_: len, destroyed: false }
}

///|
pub fn CGenStore::destroy(self : CGenStore) -> Unit {
  if self.destroyed {
    return
  }
  gen_destroy(self.ptr)
  self.destroyed = true
}

///|
pub impl @arena.GenStore for CGenStore with get(self, index) {
  if self.destroyed {
    abort("CGenStore::get called after destroy")
  }
  if index < 0 || index >= self.length_ {
    abort("CGenStore::get index out of bounds")
  }
  gen_get_(self.ptr, index)
}

///|
pub impl @arena.GenStore for CGenStore with set(self, index, generation) {
  if self.destroyed {
    abort("CGenStore::set called after destroy")
  }
  if index < 0 || index >= self.length_ {
    abort("CGenStore::set index out of bounds")
  }
  gen_set_(self.ptr, index, generation)
}

///|
pub impl @arena.GenStore for CGenStore with length(self) {
  self.length_
}

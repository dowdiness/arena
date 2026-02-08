///|
pub(open) trait BumpAllocator {
  alloc(Self, Int, Int) -> Int?
  reset(Self) -> Unit
  capacity(Self) -> Int
  used(Self) -> Int
  write_int32(Self, Int, Int) -> Bool
  read_int32(Self, Int) -> Int?
  write_double(Self, Int, Double) -> Bool
  read_double(Self, Int) -> Double?
}

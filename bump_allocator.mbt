///|
/// Contract for custom allocator implementations:
/// - If `alloc(size, align)` returns `Some(offset)`, reads/writes within that
///   allocated range must succeed until `reset`.
/// - `write_*` may return `false` only for invalid offsets or invalid allocator
///   state. Returning `false` for a freshly allocated valid slot is a contract
///   violation.
/// - `used()` must be monotonic between `reset` calls.
/// - `reset()` must restore the allocator to a reusable state.
///
/// Typed arenas depend on this contract and abort on post-alloc write failures.
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

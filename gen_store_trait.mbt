///|
pub(open) trait GenStore {
  get(Self, Int) -> Int
  set(Self, Int, Int) -> Unit
  length(Self) -> Int
}

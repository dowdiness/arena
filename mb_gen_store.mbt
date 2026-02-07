///|
pub struct MbGenStore {
  data : Array[Int]
}

///|
pub fn MbGenStore::new(slot_count : Int) -> MbGenStore {
  let count = if slot_count < 0 { 0 } else { slot_count }
  { data: Array::make(count, 0) }
}

///|
pub fn MbGenStore::get(self : MbGenStore, index : Int) -> Int {
  self.data[index]
}

///|
pub fn MbGenStore::set(
  self : MbGenStore,
  index : Int,
  generation : Int,
) -> Unit {
  self.data[index] = generation
}

///|
pub fn MbGenStore::length(self : MbGenStore) -> Int {
  self.data.length()
}

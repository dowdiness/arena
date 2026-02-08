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
pub impl GenStore for MbGenStore with get(self, index) {
  self.data[index]
}

///|
pub impl GenStore for MbGenStore with set(self, index, generation) {
  self.data[index] = generation
}

///|
pub impl GenStore for MbGenStore with length(self) {
  self.data.length()
}

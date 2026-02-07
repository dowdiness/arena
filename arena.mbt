///|
pub struct Arena {
  bump : MbBump
  gen_store : MbGenStore
  mut generation : Int
  mut count : Int
  slot_size : Int
  max_slots : Int
}

///|
pub fn Arena::new(slot_count : Int, slot_size : Int) -> Arena {
  let (capacity, max_slots) = if slot_count <= 0 || slot_size <= 0 {
    (0, 0)
  } else if slot_count > @int.max_value / slot_size {
    (0, 0)
  } else {
    (slot_count * slot_size, slot_count)
  }
  {
    bump: MbBump::new(capacity),
    gen_store: MbGenStore::new(max_slots),
    generation: 1,
    count: 0,
    slot_size,
    max_slots,
  }
}

///|
pub fn Arena::alloc(self : Arena) -> Ref? {
  if self.count >= self.max_slots {
    None
  } else {
    match self.bump.alloc(self.slot_size, 1) {
      None => None
      Some(_) => {
        let index = self.count
        self.gen_store.set(index, self.generation)
        self.count += 1
        Some(Ref::{ index, generation: self.generation })
      }
    }
  }
}

///|
pub fn Arena::is_valid(self : Arena, aref : Ref) -> Bool {
  aref.index >= 0 &&
  aref.generation == self.generation &&
  aref.index < self.count &&
  self.gen_store.get(aref.index) == aref.generation
}

///|
pub fn Arena::slot_offset(self : Arena, aref : Ref) -> Int? {
  if self.is_valid(aref) {
    Some(aref.index * self.slot_size)
  } else {
    None
  }
}

///|
pub fn Arena::reset(self : Arena) -> Unit {
  self.bump.reset()
  guard self.generation < @int.max_value else {
    abort("Arena::reset: generation counter exhausted")
  }
  self.generation += 1
  self.count = 0
}

///|
pub fn Arena::get_generation(self : Arena) -> Int {
  self.generation
}

///|
pub fn Arena::get_count(self : Arena) -> Int {
  self.count
}

///|
pub fn Arena::get_max_slots(self : Arena) -> Int {
  self.max_slots
}

///|
pub fn Arena::write_int32(
  self : Arena,
  aref : Ref,
  field_offset : Int,
  val : Int,
) -> Bool {
  if field_offset < 0 || field_offset > self.slot_size - 4 {
    return false
  }
  match self.slot_offset(aref) {
    Some(base) => self.bump.write_int32(base + field_offset, val)
    None => false
  }
}

///|
pub fn Arena::read_int32(self : Arena, aref : Ref, field_offset : Int) -> Int? {
  if field_offset < 0 || field_offset > self.slot_size - 4 {
    return None
  }
  match self.slot_offset(aref) {
    Some(base) => self.bump.read_int32(base + field_offset)
    None => None
  }
}

///|
pub fn Arena::write_double(
  self : Arena,
  aref : Ref,
  field_offset : Int,
  val : Double,
) -> Bool {
  if field_offset < 0 || field_offset > self.slot_size - 8 {
    return false
  }
  match self.slot_offset(aref) {
    Some(base) => self.bump.write_double(base + field_offset, val)
    None => false
  }
}

///|
pub fn Arena::read_double(
  self : Arena,
  aref : Ref,
  field_offset : Int,
) -> Double? {
  if field_offset < 0 || field_offset > self.slot_size - 8 {
    return None
  }
  match self.slot_offset(aref) {
    Some(base) => self.bump.read_double(base + field_offset)
    None => None
  }
}

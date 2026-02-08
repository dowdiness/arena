///|
pub struct AudioFrame {
  left : Double
  right : Double
} derive(Eq, Show)

///|
pub fn AudioFrame::new(left : Double, right : Double) -> AudioFrame {
  { left, right }
}

///|
pub impl Storable for AudioFrame with byte_size() {
  16
}

///|
pub impl Storable for AudioFrame with write_bytes(self, buf, offset) {
  Storable::write_bytes(self.left, buf, offset)
  Storable::write_bytes(self.right, buf, offset + 8)
}

///|
pub impl Storable for AudioFrame with read_bytes(buf, offset) {
  let left : Double = Storable::read_bytes(buf, offset)
  let right : Double = Storable::read_bytes(buf, offset + 8)
  { left, right }
}

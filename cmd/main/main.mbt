///|
fn main {
  let arena = @lib.Arena::new(4, 8)
  let aref = arena.alloc().unwrap()
  arena.write_double(aref, 0, 3.14) |> ignore
  println(arena.read_double(aref, 0))
}

///|
test "BufferRef::Eq same refs are equal" {
  let a = BufferRef::{ inner: Ref::{ index: 0, generation: 1 } }
  let b = BufferRef::{ inner: Ref::{ index: 0, generation: 1 } }
  inspect(a == b, content="true")
}

///|
test "BufferRef::Eq different refs are not equal" {
  let a = BufferRef::{ inner: Ref::{ index: 0, generation: 1 } }
  let b = BufferRef::{ inner: Ref::{ index: 1, generation: 1 } }
  inspect(a == b, content="false")
  let c = BufferRef::{ inner: Ref::{ index: 0, generation: 2 } }
  inspect(a == c, content="false")
}

///|
test "BufferRef::Show" {
  let bref = BufferRef::{ inner: Ref::{ index: 0, generation: 1 } }
  inspect(bref, content="{inner: {index: 0, generation: 1}}")
}

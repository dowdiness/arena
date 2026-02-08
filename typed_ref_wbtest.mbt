///|
test "TypedRef[Double]::Eq same ref" {
  let r : TypedRef[Double] = { inner: { index: 0, generation: 1 } }
  let r2 : TypedRef[Double] = { inner: { index: 0, generation: 1 } }
  inspect(r == r2, content="true")
}

///|
test "TypedRef[Double]::Eq different ref" {
  let r : TypedRef[Double] = { inner: { index: 0, generation: 1 } }
  let r2 : TypedRef[Double] = { inner: { index: 1, generation: 1 } }
  inspect(r == r2, content="false")
}

///|
test "TypedRef[Double]::Show" {
  let r : TypedRef[Double] = { inner: { index: 0, generation: 1 } }
  inspect(r, content="{inner: {index: 0, generation: 1}}")
}

///|
test "TypedRef[Int]::Show" {
  let r : TypedRef[Int] = { inner: { index: 2, generation: 3 } }
  inspect(r, content="{inner: {index: 2, generation: 3}}")
}

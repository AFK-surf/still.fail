///|
/// Two of them on one number would have one's answer end the other's ticket (outside_end) and its id taken as the
/// other's: each its own, as its name is.
test "outside kinds: each its own number and name" {
  let numbers : Map[Int, String] = {}
  let names : Map[String, Int] = {}
  for k in outside_kinds() {
    match numbers.get(k.1) {
      Some(other) => fail("outside kind \{k.1} is both \{other} and \{k.0}")
      None => numbers[k.1] = k.0
    }
    if names.contains(k.0) {
      fail("outside kind \{k.0} named twice")
    }
    names[k.0] = k.1
  }
}

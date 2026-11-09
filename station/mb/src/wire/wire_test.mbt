///|
test "lines are made of what comes, however it is cut" {
  let lines = @wire.Lines::new()
  assert_eq(lines.push(b"{\"id\":1}\n{\"id"), ["{\"id\":1}"])
  assert_eq(lines.push(b"\":2}"), [])
  assert_eq(lines.push(@utf8.encode("\n\n中\n")), ["{\"id\":2}", "", "中"])
}

///|
fn event(kind : Byte, id : Int64, rest : Bytes) -> Bytes {
  let out = [kind]
  for i = 0; i < 8; i = i + 1 {
    out.push(((id >> (8 * i)) & 0xffL).to_byte())
  }
  for b in rest {
    out.push(b)
  }
  Bytes::from_array(out)
}

///|
fn answer(error : String, json : String) -> Bytes {
  let e = @utf8.encode(error)
  let out = []
  for i = 0; i < 8; i = i + 1 {
    out.push(((e.length() >> (8 * i)) & 0xff).to_byte())
  }
  for b in e {
    out.push(b)
  }
  for b in @utf8.encode(json) {
    out.push(b)
  }
  Bytes::from_array(out)
}

///|
test "the host's events are read as host.c writes them" {
  guard @wire.Event::read(event(b'\x01', 0L, b"ab\n")) is Input(data) else { fail("not input") }
  inspect(data.length(), content="3")
  guard @wire.Event::read(event(b'\x02', 0L, b"")) is End else { fail("not the end") }
  guard @wire.Event::read(event(b'\x03', 0x0102030405L, answer("", "{\"id\":3}"))) is Answer(id, Ok(json)) else {
    fail("not an answer")
  }
  inspect(id, content="4328719365")
  inspect(json.stringify(), content="{\"id\":3}")
  guard @wire.Event::read(event(b'\x03', 9L, answer("busy", ""))) is Answer(9L, Err(ShellError(e))) else {
    fail("not an error")
  }
  inspect(e, content="busy")
  // cut short, or of a kind not known: nothing is made of it
  guard @wire.Event::read(event(b'\x03', 9L, b"\x40\x00")) is Other else { fail("read what was cut") }
  guard @wire.Event::read(b"\x01") is Other else { fail("read what was cut") }
  guard @wire.Event::read(event(b'\x09', 1L, b"")) is Other else { fail("read an unknown kind") }
}

///|
test "the shell's answers at once" {
  inspect(@wire.answered("{\"value\":{\"id\":2}}").stringify(), content="{\"id\":2}")
  inspect(@wire.answered("{\"value\":null}").stringify(), content="null")
  let failed = try {
    ignore(@wire.answered("{\"error\":\"no database 7\"}"))
    ""
  } catch {
    ShellError(e) => e
  }
  inspect(failed, content="no database 7")
  let garbled = try {
    ignore(@wire.answered("{"))
    ""
  } catch {
    ShellError(e) => e
  }
  assert_true(garbled.has_prefix("the shell's answer is not JSON"))
}

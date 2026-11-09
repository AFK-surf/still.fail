test "JavaScript's reading and writing" {
  let v = parse("{\"vault\":\"a\\ud800b\",\"b\":1,\"vault\":\"second\",\"k\\u0000x\":[1.5,true,null],\"10\":2,\"2\":{\"z\":1e400}}")
  inspect(stringify(v), content="{\"2\":{\"z\":null},\"10\":2,\"vault\":\"second\",\"b\":1,\"k\\u0000x\":[1.5,true,null]}")
  let w = parse("{\"vault\":\"a\\ud800b\"}")
  match w.get("vault") {
    Some(Str(s)) => {
      inspect(s, content="[97, 55296, 98]")
      inspect(stringify(Str(s)), content="\"a\\ud800b\"")
      inspect(text(s), content="a\u{fffd}b")
      inspect(utf16le(s), content="[97, 0, 0, 216, 98, 0]")
    }
    _ => fail("no vault")
  }
  let bad = (t : String) => (try Some(parse(t)) catch { _ => None }) is None
  inspect(bad("{\"a\":1,}"), content="true")
  inspect(bad("[01]"), content="true")
}

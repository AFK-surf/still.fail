///|
/// Node's path.posix.join and path.win32.join on the same parts (their answers as node gave them).
test "joined as Node joins" {
  let posix = [
    (["/a/b", "c"], "/a/b/c"),
    (["/a/b/", "c"], "/a/b/c"),
    (["/a//b", "./c"], "/a/b/c"),
    (["/a/b", "../c"], "/a/c"),
    (["a", "..", ".."], ".."),
    (["/", "..", "x"], "/x"),
    (["/a/b", "c/"], "/a/b/c/"),
    (["", ""], "."),
    (["/x", "grok/sessions"], "/x/grok/sessions"),
    (["rel/./x", "y"], "rel/x/y"),
  ]
  for c in posix {
    assert_eq(@nodepath.join("/", c.0), c.1)
  }
  let win = [
    (["C:\\a\\b", "c"], "C:\\a\\b\\c"),
    (["C:/a/b/", "c"], "C:\\a\\b\\c"),
    (["C:\\a", "..\\..\\b"], "C:\\b"),
    (["\\\\srv\\share\\x", "y"], "\\\\srv\\share\\x\\y"),
    (["C:", "x"], "C:\\x"),
    (["C:\\a\\b", "grok/sessions"], "C:\\a\\b\\grok\\sessions"),
  ]
  for c in win {
    assert_eq(@nodepath.join("\\", c.0), c.1)
  }
}

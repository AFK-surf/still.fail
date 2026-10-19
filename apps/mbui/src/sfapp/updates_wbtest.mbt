// The app's updates (updates.mbt) over a source of made-up builds: Home's key when one brings something, the settings'
// version row, nothing asked with no source.

///|
fn release(news : Array[String]) -> Json {
  {
    "versionCode": 2,
    "versionName": "0.1.1",
    "file": "android/stillfail-2.apk",
    "sha256": "ab",
    "size": 1000,
    "news": Json::array(news.map(fn(n) { Json::string(n) })),
  }
}

///|
fn updates_tester(r : Json, asked : Array[String]) -> @ui.Tester {
  reset()
  let src = fixture("home")
  update_version.val = 1
  set_update_source(
    Some({
      check: fn(version, now, done) {
        asked.push("\{version} \{now}")
        done(Ok(r))
      },
      url: fn(file) { "https://example.test/releases/" + file },
    }),
  )
  @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
}

///|
test "a newer build that brings something: Home's download key; the settings' row says 更新到 its version" {
  let asked = []
  let t = updates_tester(release(["列表滑得更顺"]), asked)
  t.settle() |> ignore
  t.frame()
  assert_eq(asked, ["1 false"])
  assert_true(update.available is Some(_))
  assert_eq(update_row_words(), ("更新到 0.1.1", true))
}

///|
test "none newer: the row offers to check, and asked now says 已是最新" {
  let asked = []
  let _ = updates_tester(Json::null(), asked)
  assert_eq(update_row_words(), ("检查更新", false))
  let said = []
  update_check(fixture("home"), true, done=fn(w) { said.push(w) })
  assert_eq(said, ["已是最新"])
}

///|
test "no source: nothing is asked" {
  reset()
  update_version.val = 1
  let said = []
  update_check(fixture("home"), true, done=fn(w) { said.push(w) })
  assert_eq(said.length(), 0)
}

// What the app says it shows (sfbase's shown_kind, told mbui's journal as it changes: app.mbt's app_tree) is what the
// window thread's hang reports send to PostHog with each hang and each summary (src/stillfail/reports.mbt): a kind of
// page, never which (no chat's, station's, file's or person's id, name, title or path, nothing typed). Every screen
// (corner_modes) in a phone's window and a wide one says a name of `shown_known`, written by a person, held as the
// real-size sweep opens each (real_size_wbtest.mbt, `shown_fault`): a new kind of page is not sent before someone has
// read its name here, and what has digits, dashes, slashes or more than two words (an id, an address, a path, a
// title) fails the pattern before the table is read (the user, 2026-11-11).

///|
/// Every name a screen says it shows. A new kind of page adds its name here, read first: a kind, never which.
/// (Starting, Sign in and Share are sfbase's shown_kind's too, though no mode of corner_modes opens on them.)
let shown_known : Array[String] = [
  "Starting", "Sign in", "Landing", "Share", "Home", "Chat", "Archived", "History", "NewChat", "Files", "Drive",
  "DriveRead", "DrivePlay", "Service", "Screen", "Terminal", "Place stations", "Place profiles", "Settings", "Setting Appearance",
  "Setting Me", "Setting Workspace", "Setting Security", "Setting Vault", "Setting VaultItems", "Setting VaultItem",
  "Setting Stations", "Setting Station", "Setting AdbShare", "Setting Profiles", "Setting Profile",
  "Setting NewProfile", "Setting Connects", "Setting Connect", "Setting Memory", "Setting MemoryDoc", "Setting Usage",
  "Setting Archive", "Setting KeptFiles", "Setting Fonts", "Setting AutoPolicy", "Setting RunSettings",
  "Setting AutoDecisions", "Setting AutoCompletion", "Setting BarSettings", "Setting About", "Setting Changelog",
  "Setting UsagePrices", "Setting Notifications",
]

///|
/// Whether `name` is a kind's name: a word of letters, or two with one space between them.
fn shown_like_a_kind(name : String) -> Bool {
  let words = name.split(" ").map(fn(w) { w.to_owned() }).to_array()
  words.length() >= 1 &&
  words.length() <= 2 &&
  words.iter().all(fn(w) { w.length() > 0 && w.iter().all(fn(ch) { (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') }) })
}

///|
test "the pattern a kind's name keeps to: no id, address, path or title gets through" {
  assert_true(shown_like_a_kind("Chat"))
  assert_true(shown_like_a_kind("Setting StationArchiving"))
  assert_true(shown_like_a_kind("Place stations"))
  for name in ["", "Chat ", " Chat", "Chat  x", "Place ws1/st1", "Chat 01HX", "Setting Station ws1", "a-b", "聊天"] {
    assert_false(shown_like_a_kind(name), msg=name)
  }
}

///|
/// What is wrong with what screen `at` (its window and mode) says it shows, `name`: no kind's name, or one nobody has
/// read into `shown_known`; None where it is one of them. Asked of every screen by the sweep that opens them all
/// already (real_size_wbtest.mbt's, both windows): a sweep of its own would open each a second time, 20 s more of
/// every run.
fn shown_fault(at : String, name : String) -> String? {
  if !shown_like_a_kind(name) {
    Some("\{at}: shows \"\{name}\", no kind's name (letters, one or two words): an id or a title got in")
  } else if !shown_known.contains(name) {
    Some("\{at}: shows \"\{name}\", not in shown_known (shown_wbtest.mbt): a kind, never which? add \"\{name}\" there")
  } else {
    None
  }
}

///|
test "what a screen says it shows is held to shown_known: a name not there, or no kind's name, is a fault" {
  assert_eq(shown_fault("phone chat", "Chat"), None)
  assert_true(shown_fault("phone chat", "Setting Brandnew") is Some(_))
  assert_true(shown_fault("phone chat", "Chat 01HX") is Some(_))
}

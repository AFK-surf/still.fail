// The Tester's terminals (hostapi/terminal.mbt): what a device's host keeps with libghostty-vt, kept here plainly: the
// text written, line by line, its control sequences dropped (a colour, a cursor's move: none of it drawn), carriage
// returns and backspaces done, the last `rows` lines its screen. Enough for a page's tests and pictures to show what a
// program wrote; how VT is read is the host's library's, tested there.

///|
priv struct FakeTerminal {
  mut cols : Int
  mut rows : Int
  lines : Array[String]
  mut line : Array[Char]
  mut at : Int
}

///|
// kept across runs: a Tester's terminals by their ids, the next id (each run opens its own)
let fake_terminals : Map[Int, FakeTerminal] = Map([])

///|
// kept across runs: see fake_terminals
let fake_terminal_next : Ref[Int] = Ref(0)

///|
impl @hostapi.Host for FakeHost with tm_open(_, cols, rows) {
  fake_terminal_next.val += 1
  fake_terminals[fake_terminal_next.val] = { cols, rows, lines: [], line: [], at: 0 }
  fake_terminal_next.val
}

///|
impl @hostapi.Host for FakeHost with tm_write(_, id, data) {
  guard fake_terminals.get(id) is Some(t) else { return }
  let text = @utf8.decode_lossy(data)
  let cs = text.to_array()
  let mut i = 0
  while i < cs.length() {
    let c = cs[i]
    match c {
      '\u{1b}' => {
        // a sequence: CSI to its final byte, OSC to BEL or ST, else the one after it
        i += 1
        if i < cs.length() && cs[i] == '[' {
          i += 1
          while i < cs.length() && !(cs[i] >= '@' && cs[i] <= '~') {
            i += 1
          }
        } else if i < cs.length() && cs[i] == ']' {
          while i < cs.length() && cs[i] != '\u{07}' && !(cs[i] == '\\' && cs[i - 1] == '\u{1b}') {
            i += 1
          }
        }
      }
      '\r' => t.at = 0
      '\n' => {
        t.lines.push(String::from_array(t.line))
        t.line = []
        t.at = 0
      }
      '\u{08}' => if t.at > 0 { t.at -= 1 }
      _ if c.to_int() < 0x20 => ()
      _ => {
        if t.at < t.line.length() {
          t.line[t.at] = c
        } else {
          t.line.push(c)
        }
        t.at += 1
      }
    }
    i += 1
  }
}

///|
impl @hostapi.Host for FakeHost with tm_resize(_, id, cols, rows) {
  guard fake_terminals.get(id) is Some(t) else { return }
  t.cols = cols
  t.rows = rows
}

///|
impl @hostapi.Host for FakeHost with tm_lines(_, id) {
  guard fake_terminals.get(id) is Some(t) else { return "" }
  let all = [..t.lines, String::from_array(t.line)]
  let shown = if all.length() > t.rows { all[all.length() - t.rows:].to_owned() } else { all }
  let lines : Array[Json] = shown.map(fn(l) {
    Json::array(if l == "" { [] } else { [Json::array([Json::string(l), Json::string(""), Json::string(""), Json::number(0.0)])] })
  })
  let y = shown.length() - 1
  let said : Map[String, Json] = Map([
    ("cols", Json::number(t.cols.to_double())),
    ("rows", Json::number(t.rows.to_double())),
    ("cursor", Json::array([Json::number(t.at.to_double()), Json::number(y.to_double()), Json::boolean(true)])),
    ("keys", Json::number(0.0)),
    ("lines", Json::array(lines)),
  ])
  Json::object(said).stringify()
}

///|
impl @hostapi.Host for FakeHost with tm_close(_, id) {
  fake_terminals.remove(id)
}

// A flow's trace, made and looked at (scripts/trace runs this; scripts/rerecord.sh its steps):
//
//     trace make LOG [NAME]      a scripted run's conversation with its core (MBUI_CORE_TRACE=1: CORETRACE lines on a
//                                flow's log, e2e/run.sh) made a test's: e2e/traces/NAME.trace, which a Tester gives
//                                again (src/core/replay.mbt, src/sfreplay/steps.mbt; a test reads it as it runs:
//                                @sfreplay.trace(NAME)). Bytes beside a message over MAX_BYTES (16 KB) are left out,
//                                their length kept ("bn": they come as that many zeros, a picture as none it can
//                                decode). A sign-in's tokens (the values of keys SECRET names) are put as "-".
//     trace diff OLD NEW         what a re-recording changed, at a glance: the app's asks (calls, subscriptions, their
//                                params without ids and times) more or fewer than before, and how many messages each
//                                side had. Not the JSON's diff.
//     trace mark TEST TRACE      the run's mark: the six digits the test's words and its trace share most
//     trace maxbytes TRACE…      the most bytes beside a message the traces kept (at least 16384)

///|
#borrow(path)
extern "C" fn c_read(path : Bytes) -> Bytes = "sft_read"

///|
extern "C" fn c_ok() -> Int = "sft_ok"

///|
#borrow(path, data)
extern "C" fn c_write(path : Bytes, data : Bytes) -> Int = "sft_write"

///|
#borrow(s)
extern "C" fn c_out(s : Bytes, err : Int) -> Unit = "sft_out"

///|
#borrow(name)
extern "C" fn c_getenv(name : Bytes) -> Bytes = "sft_getenv"

///|
extern "C" fn c_getcwd() -> Bytes = "sft_getcwd"

///|
extern "C" fn c_exit(code : Int) -> Unit = "sft_exit"

///|
fn read(path : String) -> String? {
  let b = c_read(@utf8.encode(path))
  if c_ok() == 0 {
    None
  } else {
    Some(@utf8.decode_lossy(b[:]))
  }
}

///|
fn say(s : String) -> Unit {
  c_out(@utf8.encode(s + "\n"), 0)
}

///|
fn die(s : String) -> Unit {
  c_out(@utf8.encode(s + "\n"), 1)
  c_exit(1)
  panic()
}

///|
fn env(name : String) -> String? {
  let v = c_getenv(@utf8.encode(name))
  if c_ok() == 0 {
    None
  } else {
    Some(@utf8.decode_lossy(v[:]))
  }
}

///|
fn re(p : String) -> @re.Regex {
  @re.Regex::new(p) catch {
    _ => panic()
  }
}

///|
fn parse(s : String) -> @rjson.Value? {
  try {
    Some(@rjson.parse(s))
  } catch {
    _ => None
  }
}

///|
fn compact(v : @rjson.Value) -> String {
  @rjson.dumps(v, compact=true, ensure_ascii=false)
}

// ---------------------------------------------------------------- make

///|
let secret_keys : Array[String] = [
  "access", "refresh", "accesstoken", "refreshtoken", "idtoken", "id_token", "token",
  "secret", "password", "code_verifier",
]

///|
/// A sign-in's tokens (a key SECRET names, its value a string) put as "-"
fn scrub(v : @rjson.Value) -> @rjson.Value {
  match v {
    Obj(kvs) =>
      Obj(
        kvs.map(fn(kv) {
          match kv.1 {
            Str(_) if secret_keys.contains(kv.0.to_lower()) => (kv.0, Str("-"))
            x => (kv.0, scrub(x))
          }
        }),
      )
    Arr(xs) => Arr(xs.map(scrub))
    x => x
  }
}

///|
/// A credential's name: a header's (Authorization, Cookie, Set-Cookie, a name saying token, key, secret, auth,
/// session, password, sig), a query's or a body's field
fn secret_name(name : String) -> Bool {
  let n = name.to_lower()
  n == "cookie" ||
  n == "set-cookie" ||
  ["auth", "token", "key", "secret", "session", "password", "sig"].iter().any(fn(w) {
    n.contains(w)
  })
}

///|
fn query_kept(path : String) -> String {
  match path.find("?") {
    None => path
    Some(q) => {
      let head = path.view(end_offset=q).to_string()
      let fields = path.view(start_offset=q + 1).to_string().split("&").map(fn(f) {
        let f = f.to_string()
        match f.find("=") {
          Some(e) if secret_name(f.view(end_offset=e).to_string()) =>
            f.view(end_offset=e).to_string() + "=-"
          _ => f
        }
      })
      head + "?" + fields.to_array().join("&")
    }
  }
}

///|
fn json_kept(j : @rjson.Value) -> @rjson.Value {
  match j {
    Obj(kvs) =>
      Obj(
        kvs.map(fn(kv) {
          (kv.0, if secret_name(kv.0) { Str("-") } else { json_kept(kv.1) })
        }),
      )
    Arr(xs) => Arr(xs.map(json_kept))
    x => x
  }
}

///|
fn hex_bytes(h : String) -> Array[Int] {
  let cs = h.to_array()
  let d = fn(c : Char) {
    if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else {
      c.to_int() - 'A'.to_int() + 10
    }
  }
  Array::makei(cs.length() / 2, fn(i) { d(cs[2 * i]) * 16 + d(cs[2 * i + 1]) })
}

///|
fn to_hex(bs : Array[Int]) -> String {
  let hex = "0123456789abcdef".to_array()
  let sb = StringBuilder::new()
  for b in bs {
    sb.write_char(hex[b >> 4])
    sb.write_char(hex[b & 15])
  }
  sb.to_string()
}

///|
/// A site's request body as mbui keeps the site's own (hostcall.mbt site_body_kept): bytes as latin-1 characters
fn body_kept(b : Array[Int]) -> Array[Int] {
  let s = String::from_array(b.map(fn(x) { Int::unsafe_to_char(x) }))
  match parse(s) {
    Some(Obj(_) as j) => {
      let k = json_kept(j)
      if k == j {
        return b
      }
      let out = compact(k)
      let cs = out.to_array()
      // (a body that wrote characters past latin-1 as \uXXXX escapes: not written back, all of it "-")
      if cs.iter().any(fn(c) { c.to_int() > 0xFF }) {
        return [0x2d]
      }
      return cs.map(fn(c) { c.to_int() })
    }
    _ => ()
  }
  if s.contains("=") && !s.contains(" ") && !s.contains("\n") {
    let k = query_kept("?" + s)
    let k = k.view(start_offset=1).to_string()
    return if k == s { b } else { k.to_array().map(fn(c) { c.to_int() }) }
  }
  if secret_name(s) {
    [0x2d]
  } else {
    b
  }
}

///|
/// A site's request as the run's app forwarded it (station.preview), kept as mbui keeps the site's own on the record
fn preview_kept(ev : @rjson.Value) -> @rjson.Value {
  let out = match ev.get("out") {
    Some(Obj(_) as o) => o
    _ => return ev
  }
  if out.get("call") != Some(Str("station.preview")) {
    return ev
  }
  let mut p = match out.get("params") {
    Some(Obj(_) as p) => p
    _ => return ev
  }
  match p.get("headers") {
    Some(Arr(hs)) =>
      p = p.set(
        "headers",
        Arr(
          hs.map(fn(h) {
            match h {
              Arr([a, _]) => {
                let name = match a {
                  Str(s) => s
                  x => @rjson.dumps(x)
                }
                if secret_name(name) {
                  Arr([a, Str("-")])
                } else {
                  h
                }
              }
              _ => h
            }
          }),
        ),
      )
    _ => ()
  }
  match p.get("path") {
    Some(Str(path)) => p = p.set("path", Str(query_kept(path)))
    _ => ()
  }
  let mut ev = ev.set("out", out.set("params", p))
  match ev.get("b") {
    Some(Str(h)) => ev = ev.set("b", Str(to_hex(body_kept(hex_bytes(h)))))
    _ => ()
  }
  ev
}

///|
fn basename(p : String) -> String {
  match p.rev_find("/") {
    Some(k) => p.view(start_offset=k + 1).to_string()
    None => p
  }
}

///|
/// os.path.abspath
fn abspath(p : String) -> String {
  let full = if p.has_prefix("/") {
    p
  } else {
    @utf8.decode_lossy(c_getcwd()[:]) + "/" + p
  }
  let parts = []
  for part in full.split("/") {
    let part = part.to_string()
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      let _ = parts.pop()
      continue
    }
    parts.push(part)
  }
  "/" + parts.join("/")
}

///|
fn root() -> String {
  match env("SF_ROOT") {
    Some(r) if r != "" => r
    _ =>
      match env("MBUI_APP_MOD") {
        Some(r) if r != "" => r
        _ => "."
      }
  }
}

///|
fn make(args : Array[String]) -> Unit {
  if args.length() < 1 {
    die("trace make LOG [NAME]")
  }
  let src = args[0]
  let max_bytes = match env("MAX_BYTES") {
    Some(v) => {
      let mut n = 0
      for c in strip_ws(v) {
        if c >= '0' && c <= '9' {
          n = n * 10 + (c.to_int() - '0'.to_int())
        }
      }
      n
    }
    None => 16384
  }
  let name = if args.length() > 1 {
    args[1]
  } else {
    let b = basename(src)
    let b = match b.rev_find(".") {
      Some(k) => b.view(end_offset=k).to_string()
      None => b
    }
    re("^\\d+-").sub(b, "")
  }
  let log = match read(src) {
    Some(t) => t
    None => {
      die("trace: cannot read \{src}")
      ""
    }
  }
  let src_abs = abspath(src)
  let lines : Array[String] = []
  let texts : Array[String] = []
  for line in log.split("\n") {
    let line = line.to_string()
    // (what the host answered, as its text recording kept it (MBUI_TEXT_RECORD=1): a Tester answers the same)
    match line.find("TEXTREC ") {
      Some(t) => {
        match parse(line.view(start_offset=t + 8).to_string()) {
          Some(j) => texts.push(compact(Obj([("textrec", j)])))
          None => ()
        }
        continue
      }
      None => ()
    }
    let i = match line.find("CORETRACE ") {
      Some(i) => i
      None => continue
    }
    let raw = match parse(line.view(start_offset=i + 10).to_string()) {
      Some(v) => v
      None => {
        die("trace: a CORETRACE line that is not JSON: \{line}")
        Null
      }
    }
    let mut ev = preview_kept(scrub(raw))
    // (a step that named the run's own log (a flow's {LOG}) as the test writes it, {LOG})
    match ev.get("step") {
      Some(Str(s)) if s.contains(src_abs) =>
        ev = ev.set("step", Str(s.replace_all(old=src_abs, new="{LOG}")))
      _ => ()
    }
    // (what the app was started with: its account's tokens put as "-" as a migrate's are; a sign-in's callback not
    // kept)
    match ev.get("env") {
      Some(Obj(_) as e) => {
        let mut e = e
        match e.get("MBUI_CORE_ACCOUNT") {
          Some(Str(a)) =>
            e = e.set(
              "MBUI_CORE_ACCOUNT",
              Str(
                match parse(a) {
                  Some(j) => compact(scrub(j))
                  None => "-"
                },
              ),
            )
          Some(_) => e = e.set("MBUI_CORE_ACCOUNT", Str("-"))
          None => ()
        }
        if e.get("MBUI_AUTH_COMPLETE") is Some(_) {
          e = e.set("MBUI_AUTH_COMPLETE", Str("-"))
        }
        ev = ev.set("env", e)
      }
      _ => ()
    }
    // (a frame the host kept, whole: what the app uploads of it is compared with it)
    match (ev.get("still"), ev.get("b")) {
      (None, Some(Str(b))) if b.length() > max_bytes * 2 =>
        ev = ev.remove("b").set("bn", Num((b.length() / 2).to_string()))
      _ => ()
    }
    lines.push(compact(ev))
  }
  for t in texts {
    lines.push(t)
  }
  if lines.length() == 0 {
    die(
      "trace: no CORETRACE lines in \{src} (was the run's app given MBUI_CORE_TRACE=1?)",
    )
  }
  let path = root() + "/e2e/traces/" + name + ".trace"
  if c_write(@utf8.encode(path), @utf8.encode(lines.join("\n") + "\n")) == 0 {
    die("trace: cannot write \{path}")
  }
  say("\{lines.length()} messages: e2e/traces/\{name}.trace")
}

// ---------------------------------------------------------------- diff

///|
let volatile : Array[String] = [
  "id", "ts", "at", "createdAt", "updatedAt", "startedAt", "endedAt", "w", "time",
  "now", "nonce", "clientKey", "key", "session", "thread", "station",
]

///|
let calm_subs : Array[(@re.Regex, String)] = [
  // a run's own: its mark, the workspace's and stations' ids (a fresh local still.fail makes new ones), ports
  (re("\\b[0-9A-HJKMNP-TV-Z]{26}\\b"), "<ws>"),
  (re("\\b[0-9a-f]{64}\\b"), "<st>"),
  (re("ember(%3A|:)c-[0-9a-f]{10}"), "<session>"),
  (re("127\\.0\\.0\\.1:\\d+"), "127.0.0.1:<port>"),
  (re("message=\\d+"), "message=<n>"),
]

///|
let six_digits : @re.Regex = re("\\d{6}")

///|
fn calm_str(s : String) -> String {
  let mut v = s
  for x in calm_subs {
    v = x.0.sub(v, x.1)
  }
  if six_digits.fullmatch(v) is Some(_) {
    "…"
  } else {
    v
  }
}

///|
fn calm(v : @rjson.Value) -> @rjson.Value {
  match v {
    Obj(kvs) => {
      let sorted = kvs.copy()
      sorted.sort_by(fn(a, b) { @rjson.str_cmp(a.0, b.0) })
      // (a key can be a run's own too: barsBy's workspace)
      Obj(
        sorted.map(fn(kv) {
          (
            calm_str(kv.0),
            if volatile.contains(kv.0) {
              Str("…")
            } else {
              calm(kv.1)
            },
          )
        }),
      )
    }
    Arr(xs) => Arr(xs.map(calm))
    Str(s) => Str(calm_str(s))
    x => x
  }
}

///|
fn truthy(v : @rjson.Value?) -> Bool {
  match v {
    None | Some(Null) | Some(Bool(false)) | Some(Str("")) | Some(Arr([])) | Some(
      Obj([])
    ) => false
    Some(Num(n)) => n.to_array().iter().any(fn(c) { c >= '1' && c <= '9' })
    _ => true
  }
}

///|
/// The app's asks of a trace (by kind and params, counted), and how many messages came in
fn asks(path : String) -> (Map[String, Int], Int) {
  let out : Map[String, Int] = Map::new()
  let mut n_in = 0
  let text = match read(path) {
    Some(t) => t
    None => {
      die("trace: cannot read \{path}")
      ""
    }
  }
  for line in text.split("\n") {
    let line = strip_ws(line.to_string())
    if line == "" {
      continue
    }
    let ev = match parse(line) {
      Some(v) => v
      None => {
        die("trace: \{path}: a line that is not JSON")
        Null
      }
    }
    if ev.get("in") is Some(_) {
      n_in += 1
      continue
    }
    let m = ev.get("out").unwrap_or(Obj([]))
    let (name, detail) = match m.get("call") {
      Some(c) =>
        (
          "call " +
          (match c {
            Str(s) => s
            x => @rjson.dumps(x)
          }),
          Some(calm(m.get("params").unwrap_or(Null))),
        )
      None =>
        match m.get("subscribe") {
          Some(sub) => {
            let topic = match sub.get("topic") {
              Some(Str(t)) => t
              _ => "?"
            }
            let rest = match sub {
              Obj(kvs) => @rjson.Value::Obj(kvs.filter(fn(kv) { kv.0 != "topic" }))
              x => x
            }
            ("subscribe " + topic, Some(calm(rest)))
          }
          None =>
            if truthy(m.get("unsubscribe")) {
              ("unsubscribe", None)
            } else if truthy(m.get("cancel")) {
              ("cancel", None)
            } else {
              ("other", Some(calm(m)))
            }
        }
    }
    let key = match detail {
      None | Some(Null) | Some(Obj([])) => name
      Some(d) =>
        name + " " + @rjson.dumps(d, sort_keys=true, ensure_ascii=false)
    }
    out[key] = out.get_or_default(key, 0) + 1
  }
  (out, n_in)
}

///|
fn first_chars(s : String, n : Int) -> String {
  let cs = s.to_array()
  if cs.length() <= n {
    s
  } else {
    String::from_array(cs[:n])
  }
}

///|
fn diff(args : Array[String]) -> Unit {
  if args.length() != 2 {
    die("trace diff OLD NEW")
  }
  let (old, old_in) = asks(args[0])
  let (new, new_in) = asks(args[1])
  let sum = fn(m : Map[String, Int]) {
    let mut s = 0
    for _, v in m {
      s += v
    }
    s
  }
  say("asks \{sum(old)} → \{sum(new)}, messages in \{old_in} → \{new_in}")
  let more = []
  for k, v in new {
    let d = v - old.get_or_default(k, 0)
    if d > 0 {
      more.push((k, d))
    }
  }
  let fewer = []
  for k, v in old {
    let d = v - new.get_or_default(k, 0)
    if d > 0 {
      fewer.push((k, d))
    }
  }
  let order = fn(a : (String, Int), b : (String, Int)) {
    let c = @rjson.str_cmp(a.0, b.0)
    if c != 0 {
      c
    } else {
      a.1 - b.1
    }
  }
  more.sort_by(order)
  fewer.sort_by(order)
  for x in more {
    say("  + \{x.1}× \{first_chars(x.0, 200)}")
  }
  for x in fewer {
    say("  - \{x.1}× \{first_chars(x.0, 200)}")
  }
  if more.length() == 0 && fewer.length() == 0 {
    say("  the same asks")
  }
}

// ---------------------------------------------------------------- mark, maxbytes

///|
/// The run's mark: the six digits (not more) the test's words and its trace share most (the first of those as
/// many), "" when they share none
fn mark(args : Array[String]) -> Unit {
  if args.length() != 2 {
    die("trace mark TEST TRACE")
  }
  let words = read(args[0]).unwrap_or("")
  let trace = read(args[1]).unwrap_or("")
  let counts : Map[String, Int] = Map::new()
  for m in re("(?<!\\d)(\\d{6})(?!\\d)").findall(trace) {
    if words.contains(m) {
      counts[m] = counts.get_or_default(m, 0) + 1
    }
  }
  let mut best = ""
  let mut most = 0
  for k, v in counts {
    if v > most {
      best = k
      most = v
    }
  }
  say(best)
}

///|
fn maxbytes(args : Array[String]) -> Unit {
  let mut most = 16384
  for path in args {
    for line in read(path).unwrap_or("").split("\n") {
      let line = strip_ws(line.to_string())
      if line == "" {
        continue
      }
      match parse(line) {
        Some(ev) =>
          match ev.get("b") {
            Some(Str(b)) => if b.length() / 2 > most { most = b.length() / 2 }
            _ => ()
          }
        None => die("trace: \{path}: a line that is not JSON")
      }
    }
  }
  say(most.to_string())
}

///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    die("trace make LOG [NAME] | diff OLD NEW | mark TEST TRACE | maxbytes TRACE…")
  }
  let rest = args[2:].to_array()
  match args[1] {
    "make" => make(rest)
    "diff" => diff(rest)
    "mark" => mark(rest)
    "maxbytes" => maxbytes(rest)
    other => die("trace: no command \{other}")
  }
}

///|
/// str.strip()
fn strip_ws(s : String) -> String {
  let cs = s.to_array()
  let ws = fn(c : Char) { c == ' ' || c == '\t' || c == '\r' || c == '\n' }
  let mut a = 0
  let mut b = cs.length()
  while a < b && ws(cs[a]) {
    a += 1
  }
  while b > a && ws(cs[b - 1]) {
    b -= 1
  }
  String::from_array(cs[a:b])
}

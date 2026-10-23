// What detlint.json says, and the rules over a MoonBit file's calls and tokens

///|
priv struct Config {
  mbt_roots : Array[String]
  framework : Array[String]
  // the scheduler itself (the frame loop, the dispatch of inputs and events, the host's bridge): the only place a
  // frame is asked for
  frame_core : Array[String]
  clock_sources : Array[String]
  queries : Array[String]
  globals_roots : Array[String]
  flows : Array[String]
  // the hosts' own sources (Java, Objective-C, C, C++, the web's host.js): host-delay
  hosts : Array[String]
  scripts : Array[String]
  skip : Array[String]
  // the token files: where a style's numbers are said (style-literal does not count them there)
  style_tokens : Array[String]
  // what tells outside of a frame: field calls ((src.call)(…): their field's name) and package functions
  effect_fields : Array[String]
  effect_calls : Array[String]
  effect_methods : Array[String]
}

///|
fn strs(v : @rjson.Value?, dflt : Array[String]) -> Array[String] {
  match v {
    Some(Arr(a)) => a.filter_map(fn(x) { x.str() })
    _ => dflt
  }
}

///|
fn sect(d : @rjson.Value, key : String) -> @rjson.Value {
  match d.get(key) {
    Some(v) => v
    None => Obj([])
  }
}

///|
fn Config::new(d : @rjson.Value) -> Config {
  let m = sect(d, "mbt")
  let be = sect(d, "build_effect")
  {
    mbt_roots: strs(m.get("roots"), ["src"]),
    framework: strs(m.get("framework"), []),
    frame_core: strs(m.get("frame_core"), []),
    clock_sources: strs(m.get("clock_sources"), []),
    queries: strs(m.get("queries"), query_default),
    globals_roots: strs(sect(d, "globals").get("roots"), []),
    flows: strs(d.get("flows"), []),
    hosts: strs(d.get("hosts"), []),
    scripts: strs(d.get("scripts"), []),
    skip: strs(d.get("skip"), []),
    style_tokens: strs(sect(d, "style").get("tokens"), []),
    effect_fields: strs(be.get("fields"), ["call", "subscribe"]),
    effect_calls: strs(be.get("calls"), build_effect_calls),
    effect_methods: strs(be.get("methods"), build_effect_methods),
  }
}

///|
fn Config::host_dirs(self : Config) -> Array[String] {
  self.framework.filter(fn(p) {
    let q = if p.has_suffix("/") {
      p.view(end_offset=p.length() - 1).to_string()
    } else {
      p
    }
    q.has_suffix("/host") || q.has_suffix("/hostapi")
  })
}

///|
fn pkg_of(rel : String) -> String {
  @sys.dirname(rel)
}

///|
fn last_name(name : String) -> String {
  let parts = name.split("::").to_array()
  parts[parts.length() - 1].to_string()
}

///|
fn lint_mbt(
  f : MbtFile,
  cfg : Config,
  out : Array[Finding],
  returns : Map[String, String],
  readers : Map[String, String],
) -> Unit {
  let app = !under(f.rel, cfg.framework)
  let frame_core = under(f.rel, cfg.frame_core)
  let clock_source = under(f.rel, cfg.clock_sources)
  let host_dir = under(f.rel, cfg.host_dirs())
  let effect_own = under(f.rel, ["src/effect", "src/effecttest"])
  let toks = f.toks
  fn add(rule : String, k : Int, what : String) {
    out.push(finding(rule, f.rel, toks[k].line, what))
  }

  for c in f.calls {
    // the interfaces given up: neither defined nor called, anywhere
    if retired.contains(c.name) &&
      (c.is_def || c.kind == "method" || c.kind == "pkg" || c.kind == "bare" || c.kind == "type") {
      add("retired-api", c.at, f.line_text(c.at))
    }
    // the same, as the framework keeps it for itself: not called by the app, nor run to by a test (its own tests
    // may read it)
    if retired_outside.contains(c.name) && !c.is_def && app && !f.in_test(c.at) {
      add("retired-api", c.at, f.line_text(c.at))
    }
    if time_fns.contains(c.name) || c.name == "frame" {
      if c.args.iter().any(fn(a) {
          a.1.iter().any(fn(i) {
            toks[i].kind == "ident" && retired_outside.contains(toks[i].text)
          })
        }) {
        add("retired-api", c.at, f.line_text(c.at))
      }
    }
    if c.is_def {
      continue
    }
    let in_t = f.in_test(c.at)
    let item = c.item
    // 1. the app asks for a frame (bare: the framework's own, in its package: h_request_frame, hostread's
    // request_frame)
    if (c.name == "request_frame" || c.name == "h_request_frame") &&
      !frame_core &&
      !in_t {
      add("frame-request", c.at, f.line_text(c.at))
    }
    // 2. settle / settled / stable, but in their own definitions
    if settle_names.contains(c.name) && (c.kind == "method" || c.kind == "pkg") {
      let own = item >= 0 &&
        f.items[item].kind == "fn" &&
        settle_defs.contains(last_name(f.items[item].name))
      let ty = if c.kind == "method" {
        f.recv_type(c.at, returns)
      } else {
        Some(c.qual)
      }
      let known = match ty {
        None => true
        Some(t) => settle_types.contains(t)
      }
      if !own && (known || c.kind == "pkg") {
        add(
          "settle",
          c.at,
          f.line_text(c.at) +
          (if ty is None { "   (receiver's type not known: counted)" } else { "" }),
        )
      }
    }
    // a fiber waiting for a frame, but the runtime's own (src/effect: its definition, its scheduler; src/effecttest:
    // its tests)
    if c.name == "next_frame" &&
      (c.kind == "pkg" || c.kind == "bare") &&
      !effect_own {
      add("frame-wait", c.at, f.line_text(c.at))
    }
    // 3. at rest, read but in an assertion (the framework's own reading of it as a frame ends: frame_core)
    if c.name == "at_rest" &&
      (c.kind == "method" || c.kind == "pkg" || c.kind == "bare") &&
      !frame_core {
      if !f.assert_args().iter().any(fn(held) { held.contains(c.at) }) {
        add("at-rest-wait", c.at, f.line_text(c.at))
      }
    }
    // the engine's own sine, exponential, power (and a Double's pow, which is @math's)
    if (c.kind == "pkg" && c.qual == "@math" && engine_math.contains(c.name)) ||
      (
        c.kind == "method" &&
        c.name == "pow" &&
        (match f.recv_type(c.at, returns) {
          None => true
          Some(t) => t == "Double"
        })
      ) {
      add("engine-math", c.at, f.line_text(c.at))
    }
    // a target waited on until it holds still
    if hold_still.contains(c.name) && (c.kind == "method" || c.kind == "bare") {
      add("at-rest-wait", c.at, f.line_text(c.at))
    }
    // the app as it is screenshotted is not the app
    if c.name == "stable" &&
      c.kind == "method" &&
      !in_t &&
      c.args.length() == 0 &&
      (match f.recv_type(c.at, returns) {
        None => true
        Some(t) => t == "Ctx"
      }) {
      add("stable-mode", c.at, f.line_text(c.at))
    }
    // 4. a bare number as a time
    if time_fns.contains(c.name) || (c.name == "frame" && c.kind == "method") {
      for a in c.args {
        let (label, idx) = a
        if c.name == "frame" && label != Some("ms") {
          continue
        }
        if c.name != "frame" && label is Some(_) {
          continue
        }
        if literal_time(f, idx) {
          add("literal-time", c.at, f.line_text(c.at))
          break
        }
      }
    }
    // 5. the app reads the clock
    if c.name == "now" &&
      app &&
      !in_t &&
      (c.kind == "method" || c.kind == "pkg") &&
      c.args.length() == 0 {
      add("app-clock", c.at, f.line_text(c.at))
    }
    // wall clock through a provider's function outside it; @ui.wall_ms, the time of day for what is shown of it,
    // only as a source's `now` (now: fn() { @ui.wall_ms() }): never what a wait or a motion is timed by
    if (c.name == "wall_ms" || c.name == "ffi_wall_ms") &&
      !clock_source &&
      !in_t &&
      !(c.qual == "@ui" && wall_as_now.search(f.line_text(c.at)) is Some(_)) {
      add("wall-clock", c.at, f.line_text(c.at))
    }
    // a random id made new each run (uuid(), random_id()): an id the app needs is drawn from what the run gives it
    // (a seed, a counter, the frames' clock), so the same run makes the same one
    if random_ids.contains(c.name) &&
      c.args.length() == 0 &&
      !clock_source &&
      !in_t {
      add("wall-clock", c.at, f.line_text(c.at))
    }
    // 6. a frame asked under a condition that reads the host or the layout
    if frame_ask.contains(c.name) &&
      (c.kind == "method" || c.kind == "pkg") &&
      !in_t &&
      !host_dir {
      let timed = c.name != "request_frame" &&
        !c.args.iter().any(fn(a) { a.0 is None && literal_time(f, a.1) })
      for cond in f.enclosing_conditions(c.at) {
        match reads_query(f, cond, cfg, readers) {
          Some(q) => {
            // a wake at a deadline while a finger is down (a long press) is the deadline, not a poll
            let parts = q.split(" ").to_array()
            if !(timed && parts[parts.length() - 1] == "pressed") {
              add("poll", c.at, "\{f.line_text(c.at)}   (under: \{q})")
              break
            }
          }
          None => ()
        }
      }
    }
    // 8. MoonBit's own hash taken out as a value (x.hash(), Hash::hash(x)): seeded per process
    if c.name == "hash" &&
      !in_t &&
      (
        (c.kind == "method" && c.args.length() == 0) ||
        (c.kind == "type" && c.qual == "Hash")
      ) {
      add("builtin-hash", c.at, f.line_text(c.at))
    }
    // 7a. @hostapi's reads in the app
    if c.kind == "pkg" &&
      c.qual == "@hostapi" &&
      host_reads.contains(c.name) &&
      app &&
      !in_t {
      add("host-read", c.at, f.line_text(c.at))
    }
  }
  // wall clock and randomness in externs' bodies and anywhere else
  if !clock_source {
    for k, t in toks {
      if t.kind == "str" && wall_words.search(t.text) is Some(_) && !f.in_test(k) {
        add("wall-clock", k, f.line_text(k))
      }
      if t.kind == "at" && t.text == "@random" && k + 2 < toks.length() {
        // @random.Rand::new() without a seed
        let mut j = k + 1
        while j < toks.length() &&
              j < k + 8 &&
              !(toks[j].kind == "op" && toks[j].text == "(") {
          j += 1
        }
        if j < toks.length() && toks[j].text == "(" && toks[j].end == j + 1 {
          add("wall-clock", k, f.line_text(k))
        }
      }
    }
  }
  // an `impl Hash for T` of one's own (its hash a value of the process's seed), and the hashed collections (their
  // order the process's)
  for k, t in toks {
    if f.in_test(k) {
      continue
    }
    if t.kind == "ident" &&
      t.text == "impl" &&
      k + 2 < toks.length() &&
      toks[k + 1].text == "Hash" &&
      toks[k + 2].text == "for" {
      add("builtin-hash", k, f.line_text(k))
    }
    if t.kind == "at" && (t.text == "@hashmap" || t.text == "@hashset") {
      add("hash-order", k, f.line_text(k))
    }
  }
  // a loop that runs the clock on while something still moves or is still to come: run until it stops
  if !frame_core {
    for k in run_until_still(f) {
      add("at-rest-wait", k, f.line_text(k))
    }
  }
  // 3. a fixed count of frames in a test
  for k, t in toks {
    if !(t.kind == "ident" && t.text == "for" && f.in_test(k)) {
      continue
    }
    // for _ in 0..<N { … .frame( … }
    let mut j = k + 1
    let rng = []
    while j < toks.length() && !(toks[j].kind == "op" && toks[j].text == "{") {
      rng.push(j)
      j += 1
    }
    if j >= toks.length() || toks[j].end < 0 {
      continue
    }
    let has_range = rng
      .iter()
      .any(fn(r) { toks[r].text == "..<" || toks[r].text == "..=" })
    let bound_lit = has_range &&
      rng
      .iter()
      .all(fn(r) {
        toks[r].kind != "ident" ||
        toks[r].text == "in" ||
        toks[r].text == "_" ||
        r == k + 1
      }) &&
      rng
      .iter()
      .any(fn(r) {
        toks[r].kind == "num" && toks[r].text != "0" && toks[r].text != "1"
      })
    if !bound_lit {
      continue
    }
    let mut b = j
    while b < toks[j].end {
      if toks[b].kind == "ident" && toks[b].text == "frame" && toks[b - 1].text == "." {
        add("frame-count", k, f.line_text(k))
        break
      }
      b += 1
    }
  }
}

///|
/// The loops (while, loop, a `for` that is not over what it is given) that run the clock on (clock_runs called in
/// them) and read what still moves or is still to come (move_reads) outside a loop within them so counted: each such
/// loop once, where it begins
fn run_until_still(f : MbtFile) -> Array[Int] {
  let toks = f.toks
  let loops : Array[(Int, Int)] = []
  for k, t in toks {
    if t.kind == "ident" && (t.text == "while" || t.text == "loop" || t.text == "for") {
      let mut j = k + 1
      while j < toks.length() && !(toks[j].kind == "op" && toks[j].text == "{") {
        j += 1
      }
      // (a `for … in` goes over what it is given, the steps of a test: not on until something stops)
      let mut over = false
      if t.text == "for" {
        for i in (k + 1)..<j {
          if toks[i].kind == "ident" && toks[i].text == "in" {
            over = true
          }
        }
      }
      if j < toks.length() && toks[j].end >= 0 && !over {
        loops.push((k, toks[j].end))
      }
    }
  }
  fn called(i : Int, names : Array[String]) -> Bool {
    toks[i].kind == "ident" &&
    names.contains(toks[i].text) &&
    i + 1 < toks.length() &&
    toks[i + 1].text == "(" &&
    i > 0 &&
    (toks[i - 1].text == "." || toks[i - 1].text == "::")
  }

  fn inside(i : Int, lp : (Int, Int)) -> Bool {
    lp.0 < i && i < lp.1
  }

  let runs = loops.filter(fn(lp) {
    let mut any = false
    for i in (lp.0 + 1)..<lp.1 {
      if called(i, clock_runs) {
        any = true
        break
      }
    }
    any
  })
  let out = []
  for lp in runs {
    let inner = runs.filter(fn(o) { o != lp && inside(o.0, lp) })
    for i in (lp.0 + 1)..<lp.1 {
      if called(i, move_reads) && !inner.iter().any(fn(o) { inside(i, o) }) {
        out.push(lp.0)
        break
      }
    }
  }
  out
}

///|
// what a box and words look like said loosely (Ctx::box, row, column, layer, text, rich): box-loose; a number in
// them, or anywhere in a style's constructors (style.mbt), style-literal
let box_look : Array[String] = [
  "dir", "w", "h", "pad", "padx", "pady", "pl", "pr", "pt", "pb", "m", "mx", "my", "ml", "mr", "mt", "mb",
  "gap", "align", "justify", "bg",
  "radius", "border", "border_color", "shadow", "shadow_color", "shadow_y", "min_w", "max_w",
  "min_h", "max_h", "clip", "opacity",
]

///|
let text_look : Array[String] = [
  "size", "weight", "color", "wrap", "w", "line", "center", "tracking", "max_lines",
]

///|
/// a count, not a look's value: no style-literal
let look_counts : Array[String] = ["max_lines"]

///|
fn loose_look(name : String) -> Array[String]? {
  match name {
    "box" | "row" | "column" | "layer" => Some(box_look)
    "text" | "rich" => Some(text_look)
    _ => None
  }
}

///|
let style_makers : Array[String] = ["style", "patch", "text_style", "text_patch"]

///|
/// style-literal, box-loose, style-exact (docs/style.md): tests are not counted
fn lint_style(f : MbtFile, cfg : Config, out : Array[Finding]) -> Unit {
  let toks = f.toks
  let tokens_file = matches(f.rel, cfg.style_tokens)
  let counted : Map[Int, Unit] = Map::new()
  fn add(rule : String, k : Int, what : String) {
    out.push(finding(rule, f.rel, toks[k].line, what))
  }

  // an Exact(…) made (not the enum's own declaration, nor a match arm's pattern)
  fn exact_at(k : Int) -> Bool {
    if !(
        toks[k].kind == "ident" &&
        toks[k].text == "Exact" &&
        k + 1 < toks.length() &&
        toks[k + 1].text == "("
      ) {
      return false
    }
    let it = f.item_of[k]
    if it >= 0 && f.items[it].kind == "enum" {
      return false
    }
    let end = toks[k + 1].end
    !(
      end >= 0 &&
      end + 1 < toks.length() &&
      (toks[end + 1].text == "=>" || toks[end + 1].text == "|")
    )
  }

  for k in 0..<toks.length() {
    if exact_at(k) && !f.in_test(k) {
      add("style-exact", k, f.line_text(k))
      if !tokens_file {
        add("style-literal", k, f.line_text(k))
        let end = if toks[k + 1].end >= 0 { toks[k + 1].end } else { k + 1 }
        for i in k..=end {
          counted[i] = ()
        }
      }
    }
  }
  if tokens_file {
    return
  }
  for c in f.calls {
    if c.is_def || f.in_test(c.at) {
      continue
    }
    let look = if c.kind == "method" { loose_look(c.name) } else { None }
    match look {
      Some(l) =>
        if c.args.iter().any(fn(a) { a.0 is Some(lb) && l.contains(lb) }) {
          add("box-loose", c.at, f.line_text(c.at))
        }
      None => ()
    }
    let maker = style_makers.contains(c.name) &&
      ((c.kind == "pkg" && c.qual == "@ui") || c.kind == "bare")
    for a in c.args {
      let (label, idx) = a
      let in_look = match (look, label) {
        (Some(l), Some(lb)) => l.contains(lb)
        _ => false
      }
      if (!maker && !in_look) || (label is Some(lb) && look_counts.contains(lb)) {
        continue
      }
      for i in idx {
        if toks[i].kind == "num" && !counted.contains(i) {
          counted[i] = ()
          add("style-literal", i, f.line_text(c.at))
        }
      }
    }
  }
}

///|
fn num_value_zero(text : String) -> Bool {
  // the number's digits before its exponent all 0 (a suffix, _ left out)
  for ch in text {
    if ch == 'e' || ch == 'E' {
      break
    }
    if ch >= '1' && ch <= '9' {
      return false
    }
  }
  true
}

///|
/// Whether a time argument is a bare number: its tokens, the clock's reads taken out (c.now(), now(), t.time()),
/// are numbers and operators only, with a number among them
fn literal_time(f : MbtFile, idx : Array[Int]) -> Bool {
  let toks = f.toks
  let skip : Map[Int, Unit] = Map::new()
  for i in idx {
    let t = toks[i]
    if t.kind == "ident" &&
      (t.text == "now" || t.text == "time") &&
      i + 1 < toks.length() &&
      toks[i + 1].text == "(" {
      let e = if toks[i + 1].end >= 0 { toks[i + 1].end } else { i + 1 }
      for x in i..=e {
        skip[x] = ()
      }
      let mut j = i - 1
      while j >= 0 &&
            toks[j].text == "." &&
            j - 1 >= 0 &&
            (toks[j - 1].kind == "ident" || toks[j - 1].kind == "at") {
        skip[j] = ()
        skip[j - 1] = ()
        j -= 2
      }
    }
  }
  let rest = idx.filter(fn(i) { !skip.contains(i) }).map(fn(i) { toks[i] })
  if rest.length() == 0 ||
    (
      rest.iter().all(fn(t) { t.kind != "num" || num_value_zero(t.text) }) &&
      skip.length() == 0
    ) {
    return false // no time at all (frame(ms=0.0)) is not a guess
  }
  if rest.iter().any(fn(t) { t.kind == "ident" || t.kind == "at" || t.kind == "str" }) {
    return false
  }
  rest.iter().any(fn(t) { t.kind == "num" })
}

///|
fn reader_key(pkg : String, name : String) -> String {
  pkg + "\u{1f}" + name
}

///|
fn reads_query(
  f : MbtFile,
  cond : Array[Int],
  cfg : Config,
  readers : Map[String, String],
) -> String? {
  let toks = f.toks
  for i in cond {
    let t = toks[i]
    if t.kind == "ident" && i + 1 < toks.length() && toks[i + 1].text == "(" {
      let prev_dot = i > 0 && toks[i - 1].text == "."
      if !prev_dot {
        match readers.get(reader_key(pkg_of(f.rel), t.text)) {
          Some(r) => return Some(t.text + "() → " + r)
          None => ()
        }
      }
      if prev_dot &&
        i >= 2 &&
        toks[i - 2].kind == "at" &&
        toks[i - 2].text == "@hostapi" {
        return Some("@hostapi." + t.text)
      }
      if cfg.queries.contains(t.text) && prev_dot {
        return Some(t.text)
      }
      if t.text.has_prefix("h_") &&
        cfg.queries.contains(t.text.view(start_offset=2).to_string()) {
        return Some(t.text)
      }
    }
  }
  None
}

///|
/// The package's own functions that read the host or the layout, themselves or through another such function of
/// their package: {(package dir, name): what they read}
fn host_readers(files : Array[MbtFile], cfg : Config) -> Map[String, String] {
  let bodies : Map[String, (MbtFile, Int, Int)] = Map::new()
  for f in files {
    if f.test_file {
      continue
    }
    let pkg = pkg_of(f.rel)
    for it in f.items {
      if it.kind == "fn" && it.name != "" && !it.name.contains("::") {
        bodies[reader_key(pkg, it.name)] = (f, it.start, it.end)
      }
    }
  }
  let readers : Map[String, String] = Map::new()
  let mut changed = true
  while changed {
    changed = false
    for key, b in bodies {
      if readers.contains(key) {
        continue
      }
      let (f, s, e) = b
      match reads_query(f, Array::makei(e - s + 1, fn(i) { s + i }), cfg, readers) {
        Some(q) => {
          readers[key] = q
          changed = true
        }
        None => ()
      }
    }
  }
  readers
}

///|
fn trim(s : String) -> String {
  s.trim(chars=" \t\r\n").to_string()
}

///|
/// 7b: per package under globals.roots, every top-level let of a non-plain type is put back by the package's reset
/// (reset, reset_globals, a function given to on_reset, and what those call) or says why not
fn lint_globals(files : Array[MbtFile], cfg : Config, out : Array[Finding]) -> Unit {
  let pkgs : Map[String, Array[MbtFile]] = Map::new()
  for f in files {
    if f.test_file || !under(f.rel, cfg.globals_roots) {
      continue
    }
    let p = pkg_of(f.rel)
    match pkgs.get(p) {
      Some(a) => a.push(f)
      None => pkgs[p] = [f]
    }
  }
  let alias : Map[String, String] = Map::new()
  for p, _ in pkgs {
    alias[@sys.basename(p)] = p
  }
  let fns : Map[String, Array[Array[Tok]]] = Map::new() // (pkg, name) -> [token lists]
  fn add_fn(key : String, body : Array[Tok]) {
    match fns.get(key) {
      Some(a) => a.push(body)
      None => fns[key] = [body]
    }
  }

  let roots : Array[(String, String)] = []
  let lets : Array[(String, MbtFile, Item)] = []
  for pkg, fs in pkgs {
    for f in fs {
      for it in f.items {
        let body = f.toks[it.start:@cmp.minimum(it.end + 1, f.toks.length())].to_array()
        if it.kind == "fn" {
          add_fn(reader_key(pkg, it.name), body)
          if it.name == "reset" || it.name == "reset_globals" {
            roots.push((pkg, it.name))
          }
        } else if it.kind == "let" {
          lets.push((pkg, f, it))
        }
      }
      for c in f.calls {
        if c.name == "on_reset" && c.args.length() > 0 {
          let ts = c.args[0].1.map(fn(i) { f.toks[i] })
          if ts.length() == 1 && ts[0].kind == "ident" {
            roots.push((pkg, ts[0].text))
          } else {
            let name = "<on_reset \{f.rel}:\{f.toks[c.at].line}>"
            add_fn(reader_key(pkg, name), ts)
            roots.push((pkg, name))
          }
        }
      }
    }
  }
  let said : Map[String, Map[String, Unit]] = Map::new()
  for p, _ in pkgs {
    said[p] = Map::new()
  }
  let seen : Map[String, Unit] = Map::new()
  let todo = roots.copy()
  while true {
    let (pkg, name) = match todo.pop() {
      Some(x) => x
      None => break
    }
    let key = reader_key(pkg, name)
    if seen.contains(key) || !fns.contains(key) {
      continue
    }
    seen[key] = ()
    for body in fns[key] {
      for i, t in body {
        if t.kind != "ident" {
          continue
        }
        if !(i > 0 && body[i - 1].text == ".") { // a field of the same name is not the global
          said[pkg][t.text] = ()
        }
        if i + 1 < body.length() && body[i + 1].text == "(" {
          let q = if i >= 2 && body[i - 1].text == "." && body[i - 2].kind == "at" {
            Some(body[i - 2].text)
          } else {
            None
          }
          let p = match q {
            Some(q) => alias.get(q.view(start_offset=1).to_string())
            None => Some(pkg)
          }
          if p is Some(p) {
            todo.push((p, t.text))
          }
        }
        if i >= 2 && body[i - 1].text == "." && body[i - 2].kind == "at" {
          match alias.get(body[i - 2].text.view(start_offset=1).to_string()) {
            Some(p) => said[p][t.text] = ()
            None => ()
          }
        }
      }
    }
  }
  for l in lets {
    let (pkg, f, it) = l
    let ts = f.toks[it.start:@cmp.minimum(it.end + 1, f.toks.length())].to_array()
    // let NAME (: TYPE)? = VALUE
    let mut k = 0
    while k < ts.length() && ts[k].text != "let" {
      k += 1
    }
    if k + 1 >= ts.length() || ts[k + 1].kind != "ident" {
      continue
    }
    let name = ts[k + 1].text
    let ty = []
    let mut j = k + 2
    if j < ts.length() && ts[j].text == ":" {
      j += 1
      while j < ts.length() && ts[j].text != "=" {
        ty.push(ts[j])
        j += 1
      }
    }
    let value = if j < ts.length() { ts[j + 1:].to_array() } else { [] }
    if ty.length() > 0 &&
      ty.iter().all(fn(t) { t.kind != "ident" || plain_types.contains(t.text) }) {
      continue
    }
    if ty.length() > 0 &&
      ty[0].text == "(" &&
      ty[0].end >= 0 &&
      ty.iter().any(fn(t) { t.text == "->" }) &&
      !ty
      .iter()
      .any(fn(t) {
        ["Ref", "Array", "Map", "Set", "FixedArray"].contains(t.text)
      }) {
      continue // a function: a top-level let cannot be set again
    }
    if ty.length() == 0 &&
      value.length() == 1 &&
      (value[0].kind == "num" || value[0].kind == "str") {
      continue
    }
    if ty.length() == 0 &&
      value.length() > 0 &&
      value
      .iter()
      .all(fn(t) {
        t.kind == "num" ||
        t.kind == "str" ||
        t.kind == "op" ||
        t.text == "true" ||
        t.text == "false"
      }) {
      continue
    }
    // the comment over it
    let mut above = it.line - 1
    while above >= 1 && trim(f.lines[above - 1]) == "" {
      above -= 1
    }
    let mut kept = above >= 1 &&
      trim(f.lines[above - 1]).has_prefix("// kept across runs:")
    // doc comments (///) between: look over them
    let mut a2 = above
    while !kept && a2 >= 1 && trim(f.lines[a2 - 1]).has_prefix("//") {
      if trim(f.lines[a2 - 1]).has_prefix("// kept across runs:") {
        kept = true
      }
      a2 -= 1
    }
    if kept || said[pkg].contains(name) {
      continue
    }
    let tytext = ty.map(fn(t) { t.text }).join(" ")
    out.push(
      finding(
        "globals",
        f.rel,
        it.line,
        "\{name} : \{if tytext == "" { "(inferred)" } else { tytext }}",
      ),
    )
  }
}

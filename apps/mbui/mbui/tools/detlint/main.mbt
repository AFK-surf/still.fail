// detlint: what a run's determinism must not rest on: a guessed time, a wait for the app to "settle", a frame the
// app asks for itself, the machine's own clock. mbui runs it on itself; still.fail's apps/mbui runs the one of the
// mbui it pins ($MBUI_DIR/scripts/detlint apps/mbui) with its own apps/mbui/detlint.json.
//
//     scripts/detlint [ROOT]            check ROOT (default: mbui) against ROOT/detlint.json
//     scripts/detlint ROOT --update     write the counts found as the new bar (never above the old one;
//                                       --update=raise to raise it, said why in the commit)
//     scripts/detlint ROOT --list RULE  every finding of RULE, file:line
//
// The bar (a ratchet): detlint.json keeps each rule's count of findings, file by file, and each file is held to its
// own: one more in any file fails (a finding moved to another file too), naming it and its lines; fewer fails too,
// until --update lowers the bar (the migration's own commit: what was moved off stays off). A rule whose bar is 0 is
// simply forbidden. docs/detlint.md says each rule; rule_words (rules.mbt) is what a failure prints.
//
// An exception is written on the line itself or on the line above it, with its reason:
//
//     c.request_frame() // det-ok(frame-request): the bench mode draws every frame on purpose
//     # det-ok(script-wait): the emulator's boot has no event to wait for
//
// They are printed with their reasons, and counted (detlint.json's `excused`, by rule and file), and only go down:
// marking a finding det-ok does not make it go away. app-clock alone (swappable: a time shown is right) lets an
// exception take the place of a finding there was (found and excused together never above their bar).
//
// What it reads: MoonBit through a lexer of its own (file.mbt), a call being NAME ( … ) with what is before it (a
// receiver `.`, a package `@pkg.`, a type `T::`) and its arguments split at the top level, the enclosing top-level
// item (a `test` block, a `fn`) and blocks with their headers (if / while / match / guards). It does not know types:
// `x.request_frame()` is the Ctx's for any x. Where that is wrong, see "Limits" in docs/detlint.md.

///|
let drive_wait : @re.Regex = rx("^\\s*(wait|linger)\\s+[0-9]")

///|
/// a drive's `rest` step: a flow's line, or a line of drive text in a string (a test's, a script's)
let drive_rest : @re.Regex = rx("^\\s*rest\\s*(#.*)?$")

///|
let drive_rest_text : @re.Regex = rx("(\\\\n|^\\s*#\\||\"|')rest\\s*(\\\\n|\"|'|$)")

///|
/// a picture at the app's rest
let shot_rest : @re.Regex = rx("\\b(MBUI_SHOT_MS|shot_at|SHOT_AT)\\s*=\\s*[\"']?rest\\b")

///|
/// a picture of the app taken off a device, an emulator or a simulator
let device_shots : Array[@re.Regex] = [
  rx("\\bscreencap\\b"),
  rx("\\bsimctl\\s+io\\b.*\\bscreenshot\\b"),
]

///|
let script_waits : Array[@re.Regex] = [
  rx("(?<![\\w-])sleep\\s+[\"'$0-9.]"),
  rx("\\bMBUI_SHOT_AT=[\"'$0-9]"),
  rx("\\bsetTimeout\\(.*[^\\w.][0-9]"),
  rx("\\bwaitForTimeout\\("),
  rx("\\btime\\.sleep\\("),
]

///|
let page_settle : @re.Regex = rx("\\b__mb\\w*\\.(?:settled|unsettled)\\b")

///|
/// a host doing something a fixed time later: Android's Handler, Apple's GCD and a selector's delay, Windows' timers,
/// GLib's (Linux's)
let host_delays : Array[@re.Regex] = [
  rx("\\bpostDelayed\\("),
  rx("\\bdispatch_after\\("),
  rx("afterDelay:"),
  rx("\\bSetTimer\\("),
  rx("\\bCreateTimerQueueTimer\\("),
  rx("\\bsetTimeout\\("),
  rx("\\bg_timeout_add(?:_full|_seconds)?\\("),
]

///|
/// a test's end without its idle check: Tester::settle's, a replay's Flow::end's (an argument, not a declaration)
let unsettled_ok : @re.Regex = rx("\\bunsettled_ok\\s*=")

///|
fn find_chars(s : Array[Char], w : String) -> Int {
  let cs = w.to_array()
  let mut i = 0
  while i + cs.length() <= s.length() {
    let mut ok = true
    for k, c in cs {
      if s[i + k] != c {
        ok = false
        break
      }
    }
    if ok {
      return i
    }
    i += 1
  }
  -1
}

///|
/// A library's package (moon.pkg `rel`): each import it names that is not among `allowed` (prefixes).
fn lint_library(rel : String, src : String, allowed : Array[String], out : Array[Finding]) -> Unit {
  for n0, line in src.split("\n").to_array() {
    let line = line.to_string()
    let s = line.trim_start(chars=" \t\r\n\u{b}\u{c}").to_string()
    if s.has_prefix("//") {
      continue
    }
    // every quoted name with a slash in it: a package
    let parts = line.split("\"").to_array()
    let mut i = 1
    while i < parts.length() {
      let name = parts[i].to_string()
      if name.contains("/") && !name.contains(" ") && !allowed.iter().any(fn(a) { name.has_prefix(a) }) {
        out.push(finding("library-import", rel, n0 + 1, trim(line)))
        break
      }
      i = i + 2
    }
  }
}

///|
fn lint_lines(
  rel : String,
  src : String,
  rule : String,
  pats : Array[@re.Regex],
  out : Array[Finding],
  comment : String,
) -> Unit {
  for n0, line in src.split("\n").to_array() {
    let line = line.to_string()
    let s = line.trim_start(chars=" \t\r\n\u{b}\u{c}").to_string()
    if s.has_prefix(comment) && !s.contains("det-ok(") {
      continue
    }
    let cs = line.to_array()
    for p in pats {
      match p.search_chars_from(cs, 0) {
        Some(m) => {
          // in a comment after the code
          let ci = find_chars(cs, " " + comment + " ")
          if ci >= 0 && ci < m.start() {
            continue
          }
          out.push(finding(rule, rel, n0 + 1, trim(line)))
          break
        }
        None => ()
      }
    }
  }
}

///|
fn excuse(findings : Array[Finding], texts : Map[String, Array[String]]) -> Unit {
  for fd in findings {
    let lines = match texts.get(fd.file) {
      Some(l) => l
      None => continue
    }
    for ln in [fd.line, fd.line - 1] {
      if ln < 1 || ln > lines.length() {
        continue
      }
      match exc_re.search(lines[ln - 1]) {
        Some(m) => {
          let rules = m.get(1).split(",").map(fn(r) { trim(r.to_string()) }).to_array()
          if rules.contains(fd.rule) {
            let reason = trim(m.get(2))
            if reason == "" {
              fd.excused = None
              fd.what = fd.what + "   (det-ok without a reason: not taken)"
            } else {
              fd.excused = Some(reason)
            }
            break
          }
        }
        None => ()
      }
    }
  }
}

///|
fn read(path : String) -> String {
  match @sys.read_text(path) {
    Some(s) => s
    None => ""
  }
}

///|
fn sorted(names : Array[String]) -> Array[String] {
  let a = names.copy()
  a.sort_by(@rjson.str_cmp)
  a
}

///|
fn lines_of(src : String) -> Array[String] {
  src.split("\n").map(fn(l) { l.to_string() }).to_array()
}

///|
fn has_any_suffix(n : String, sufs : Array[String]) -> Bool {
  sufs.iter().any(fn(s) { n.has_suffix(s) })
}

///|
/// What detlint reads a file as: 0 nothing, 1 a package's moon.pkg, 2 MoonBit, 3 a flow, 4 a script, 5 a host's source
fn kind_of(rel : String, cfg : Config) -> Int {
  let n = @sys.basename(rel)
  if matches(rel, cfg.skip) {
    0
  } else if n == "moon.pkg" && under(rel, cfg.mbt_roots) {
    1
  } else if n.has_suffix(".mbt") && under(rel, cfg.mbt_roots) {
    2
  } else if matches(rel, cfg.flows) {
    3
  } else if matches(rel, cfg.scripts) {
    4
  } else if matches(rel, cfg.hosts) {
    5
  } else {
    0
  }
}

///|
/// The files under root detlint reads, (path relative to root, text), as os.walk goes: a directory's files, then
/// its directories, each sorted
fn sources(root : String, cfg : Config) -> Array[(String, String)] {
  let out = []
  fn walk(rd : String) -> Unit {
    let dir = if rd == "" { root } else { @sys.join(root, rd) }
    let files = []
    let dirs = []
    for n in sorted(@sys.list_dir(dir)) {
      let path = @sys.join(dir, n)
      let rel = if rd == "" { n } else { rd + "/" + n }
      if @sys.is_dir(path) {
        if !n.has_prefix(".") &&
          !["_build", "node_modules", "target", ".mooncakes", "out"].contains(n) &&
          !matches(rel, cfg.skip) &&
          !@sys.is_link(path) { // (os.walk lists a link to a directory but does not go in)
          dirs.push(rel)
        }
      } else if kind_of(rel, cfg) != 0 {
        files.push((rel, path))
      }
    }
    for f in files {
      out.push((f.0, read(f.1)))
    }
    for d in dirs {
      walk(d)
    }
  }

  walk("")
  out
}

///|
fn collect(root : String, cfg : Config) -> Array[Finding] {
  let files = sources(root, cfg)
  lap("read")
  lint_sources(files, cfg)
}

///|
fn lint_sources(files : Array[(String, String)], cfg : Config) -> Array[Finding] {
  let findings = []
  let texts : Map[String, Array[String]] = Map::new()
  let mbts : Array[MbtFile] = []
  for x in files {
    let (rel, src) = x
    let kind = kind_of(rel, cfg)
    if kind != 0 {
      texts[rel] = lines_of(src)
    }
    match kind {
      1 => {
        if !src.contains("is-main") {
          lint_lines(rel, src, "host-import", [host_import], findings, "//")
        }
        if under(rel, cfg.library) {
          lint_library(rel, src, cfg.library_imports, findings)
        }
      }
      2 => {
        let t0 = @env.now()
        mbts.push(MbtFile::new(rel, rel, src))
        lex_ms.val += @env.now() - t0
        lint_lines(rel, src, "unsettled-ok", [unsettled_ok], findings, "//")
        lint_lines(rel, src, "at-rest-wait", [drive_rest_text, shot_rest], findings, "//")
      }
      3 => {
        lint_lines(rel, src, "flow-wait", [drive_wait], findings, "#")
        lint_lines(rel, src, "at-rest-wait", [drive_rest], findings, "#")
      }
      4 => {
        let comment = if has_any_suffix(rel, [".mjs", ".js", ".ts"]) {
          "//"
        } else {
          "#"
        }
        lint_lines(rel, src, "script-wait", script_waits, findings, comment)
        lint_lines(rel, src, "page-settle", [page_settle], findings, comment)
        lint_lines(rel, src, "device-shot", device_shots, findings, comment)
        lint_lines(rel, src, "at-rest-wait", [shot_rest, drive_rest_text], findings, comment)
        if matches(rel, cfg.hosts) {
          lint_lines(rel, src, "host-delay", host_delays, findings, "//")
        }
      }
      5 => lint_lines(rel, src, "host-delay", host_delays, findings, "//")
      _ => ()
    }
  }
  if times_on {
    @sys.eprintln("detlint: of which MbtFile::new \{lex_ms.val} ms")
  }
  lap("lexed, lines")
  let returns = Map::new()
  for f in mbts {
    for k, v in f.returns() {
      returns[k] = v
    }
  }
  let readers = host_readers(mbts, cfg)
  lap("host readers")
  for f in mbts {
    lint_mbt(f, cfg, findings, returns, readers)
    lint_style(f, cfg, findings)
    lint_style_text(f, findings)
  }
  lap("calls, style")
  lint_globals(mbts, cfg, findings)
  lap("globals")
  lint_build_effects(mbts, cfg, findings)
  lap("build effects")
  excuse(findings, texts)
  findings
}

// ---------------------------------------------------------------------------------------------------------------------
// The bar, the report

///|
/// file -> count, in the order first counted
priv struct Counts {
  m : Map[String, Int]
}

///|
fn Counts::new() -> Counts {
  { m: Map::new() }
}

///|
fn Counts::at(self : Counts, p : String) -> Int {
  self.m.get(p).unwrap_or(0)
}

///|
fn Counts::total(self : Counts) -> Int {
  let mut n = 0
  for _, v in self.m {
    n += v
  }
  n
}

///|
fn tally(findings : Array[Finding], excused : Bool) -> Map[String, Counts] {
  let counts = Map::new()
  for r in rule_names {
    counts[r] = Counts::new()
  }
  for fd in findings {
    if (fd.excused is Some(_)) == excused {
      let c = counts[fd.rule]
      c.m[fd.file] = c.at(fd.file) + 1
    }
  }
  counts
}

///|
/// the rules where an exception may take the place of a finding there was (docs/detlint.md: a time shown is right);
/// elsewhere an exception's count only goes down, apart from the findings'
let swappable : Array[String] = ["app-clock"]

///|
fn union_keys(a : Counts, b : Counts) -> Array[String] {
  let s : Map[String, Unit] = Map::new()
  for k, _ in a.m {
    s[k] = ()
  }
  for k, _ in b.m {
    s[k] = ()
  }
  sorted(s.keys().collect())
}

///|
/// The files (of one rule) above their bar: (file, found, its bar, found and excused, their bar)
fn over(
  cf : Counts,
  ce : Counts,
  bf_ : Counts,
  be_ : Counts,
  rule : String,
) -> Array[(String, Int, Int, Int, Int)] {
  let out = []
  for p in union_keys(cf, ce) {
    let f = cf.at(p)
    let e = ce.at(p)
    let bf = bf_.at(p)
    let be = be_.at(p)
    if f > bf || (if swappable.contains(rule) { f + e > bf + be } else { e > be }) {
      out.push((p, f, bf, f + e, bf + be))
    }
  }
  out
}

///|
/// The files (of one rule) below their bar: found fewer, or found and excused fewer
fn under_bar(cf : Counts, ce : Counts, bf_ : Counts, be_ : Counts) -> Array[String] {
  let out = []
  for p in union_keys(bf_, be_) {
    let f = cf.at(p)
    let e = ce.at(p)
    let bf = bf_.at(p)
    let be = be_.at(p)
    if f < bf || f + e < bf + be {
      out.push(p)
    }
  }
  out
}

///|
fn parse_int(s : String) -> Int {
  let mut n = 0
  for ch in s {
    if ch >= '0' && ch <= '9' {
      n = n * 10 + (ch.to_int() - '0'.to_int())
    }
  }
  n
}

///|
/// a rule's bar in detlint.json (counts or excused): None when the rule has none
fn bar_of(conf : @rjson.Value, sect_name : String, rule : String) -> Counts? {
  match conf.get(sect_name) {
    Some(s) =>
      match s.get(rule) {
        Some(Obj(kv)) => {
          let c = Counts::new()
          for x in kv {
            match x.1 {
              Num(n) => c.m[x.0] = parse_int(n)
              _ => ()
            }
          }
          Some(c)
        }
        Some(Null) | None => None
        Some(_) => Some(Counts::new())
      }
    None => None
  }
}

///|
fn pad_right(s : String, w : Int) -> String {
  let n = s.to_array().length()
  if n >= w {
    s
  } else {
    s + String::make(w - n, ' ')
  }
}

///|
fn pad_left(s : String, w : Int) -> String {
  let n = s.to_array().length()
  if n >= w {
    s
  } else {
    String::make(w - n, ' ') + s
  }
}

///|
fn excused_note(fd : Finding) -> String {
  match fd.excused {
    Some(r) => "   [det-ok: \{r}]"
    None => ""
  }
}

///|
fn run(argv : Array[String], out : Array[String], err : Array[String]) -> Int {
  let args = argv.filter(fn(a) { !a.has_prefix("--") })
  let flags = argv.filter(fn(a) { a.has_prefix("--") })
  let root = @sys.abspath(
    if args.length() > 0 {
      args[0]
    } else {
      match @sys.getenv("DETLINT_HOME") {
        Some(h) => @sys.join(h, "..")
        None => "."
      }
    },
  )
  let root = normpath(root)
  let conf_path = @sys.join(root, "detlint.json")
  if !@sys.exists(conf_path) {
    err.push("detlint: no \{conf_path}")
    return 2
  }
  let conf = @rjson.parse(read(conf_path)) catch {
    @rjson.JsonError(e) => {
      err.push("detlint: \{conf_path}: \{e}")
      return 2
    }
  }
  let cfg = Config::new(conf)
  let findings = collect(root, cfg)
  if flags.contains("--list") {
    let want = if args.length() > 1 { Some(args[1]) } else { None }
    let order = Array::makei(findings.length(), fn(i) { i })
    order.sort_by(fn(a, b) {
      let x = findings[a]
      let y = findings[b]
      let c = @rjson.str_cmp(x.rule, y.rule)
      if c != 0 {
        return c
      }
      let c = @rjson.str_cmp(x.file, y.file)
      if c != 0 {
        return c
      }
      if x.line != y.line {
        return x.line.compare(y.line)
      }
      a.compare(b)
    })
    for i in order {
      let fd = findings[i]
      if want is None || want == Some(fd.rule) {
        let ex = match fd.excused {
          Some(r) => "   [det-ok: \{r}]"
          None => ""
        }
        out.push("\{fd.rule}\t\{fd.file}:\{fd.line}\t\{fd.what}\{ex}")
      }
    }
    return 0
  }
  let found = tally(findings, false)
  let excused = tally(findings, true)
  let update = flags.search_by(fn(a) { a.has_prefix("--update") }).map(fn(i) { flags[i] })
  match update {
    Some(update) => {
      let counts = []
      let exc = []
      let summary = []
      for r in rule_names {
        let nf = Counts::new()
        let ne = Counts::new()
        for k, v in found[r].m {
          nf.m[k] = v
        }
        for k, v in excused[r].m {
          ne.m[k] = v
        }
        match bar_of(conf, "counts", r) {
          Some(bf) if update != "--update=raise" => {
            let be = bar_of(conf, "excused", r).unwrap_or(Counts::new())
            for o in over(found[r], excused[r], bf, be, r) {
              let (p, f, b, fe, bfe) = o
              err.push(
                "detlint: \{r} in \{p} is above its bar (\{f} found, \{fe} with det-ok; the bar \{b}, \{bfe}): kept (--update=raise to raise it, and say why)",
              )
              nf.m[p] = bf.at(p)
              ne.m[p] = be.at(p)
            }
          }
          _ => ()
        }
        let cobj = []
        for p in sorted(nf.m.keys().collect()) {
          if nf.at(p) != 0 {
            cobj.push((p, @rjson.Value::Num(nf.at(p).to_string())))
          }
        }
        let eobj = []
        for p in sorted(ne.m.keys().collect()) {
          if ne.at(p) != 0 {
            eobj.push((p, @rjson.Value::Num(ne.at(p).to_string())))
          }
        }
        counts.push((r, @rjson.Value::Obj(cobj)))
        exc.push((r, @rjson.Value::Obj(eobj)))
        let ct = nf.total()
        let et = ne.total()
        summary.push("\{r} \{ct}" + (if eobj.length() > 0 { " (+\{et} det-ok)" } else { "" }))
      }
      let conf = conf.set("counts", Obj(counts)).set("excused", Obj(exc))
      let _ = @sys.write_text(
        conf_path,
        @rjson.dumps(conf, ensure_ascii=false, indent=2) + "\n",
      )
      out.push("detlint: bars written: " + summary.join(", "))
      return 0
    }
    None => ()
  }
  let mut bad = false
  out.push(
    "detlint (\{@sys.basename(root)}): rule, found / bar, det-ok / bar (each file against its own)",
  )
  for r in rule_names {
    let cf = found[r]
    let ce = excused[r]
    let notes = []
    let mut line = "  \{pad_right(r, 14)} \{pad_left(cf.total().to_string(), 5)} / "
    match bar_of(conf, "counts", r) {
      None => {
        bad = true
        line = line + "-"
        notes.push("    \{r}: no bar in detlint.json (scripts/detlint --update)")
      }
      Some(bf) => {
        let be = bar_of(conf, "excused", r).unwrap_or(Counts::new())
        line = line +
          "\{pad_right(bf.total().to_string(), 5)} \{pad_left(ce.total().to_string(), 4)} / \{pad_right(be.total().to_string(), 4)}"
        if bf.total() == 0 && be.total() == 0 {
          line = line + "  forbidden"
        }
        for o in over(cf, ce, bf, be, r) {
          let (p, f, b, fe, bfe) = o
          bad = true
          if f > b {
            notes.push("    \{r}: \{p}: \{f} > \{b}: \{rule_words[r]}")
          } else {
            notes.push(
              "    \{r}: \{p}: \{fe - f} det-ok, the bar \{bfe - b}: " +
              (if swappable.contains(r) {
                "an exception may only take the place of a finding there was"
              } else {
                "this rule's exceptions only go down (a finding marked det-ok is still a finding)"
              }),
            )
          }
          for fd in findings {
            if fd.rule == r && fd.file == p {
              notes.push("        \{p}:\{fd.line}  \{fd.what}" + excused_note(fd))
            }
          }
          if f > b {
            notes.push(
              "      an exception says why on its line (`det-ok(\{r}): <why>`), in place of a finding there was",
            )
          }
        }
        let lower = under_bar(cf, ce, bf, be)
        if lower.length() > 0 {
          bad = true
          notes.push(
            "    \{r}: fewer than the bar in \{lower.join(", ")}: lower it to what is now (scripts/detlint --update), so it stays there",
          )
        }
      }
    }
    out.push(line)
    for fd in findings {
      match fd.excused {
        Some(why) if fd.rule == r => out.push("      det-ok \{fd.file}:\{fd.line}: \{why}")
        _ => ()
      }
    }
    for x in notes {
      out.push(x)
    }
  }
  if bad {
    1
  } else {
    0
  }
}

///|
/// a/b/../c → a/c, a/./b → a/b
fn normpath(p : String) -> String {
  let parts = []
  for s in p.split("/") {
    let s = s.to_string()
    if s == "" || s == "." {
      continue
    }
    if s == ".." {
      let _ = parts.pop()
      continue
    }
    parts.push(s)
  }
  "/" + parts.join("/")
}

///|
fn main {
  let argv = @env.args()
  let out = []
  let err = []
  let code = run(argv[1:].to_array(), out, err)
  for l in err {
    @sys.eprintln(l)
  }
  if out.length() > 0 {
    @sys.out(out.join("\n") + "\n")
  }
  @sys.exit(code)
}

///|
/// DETLINT_TIMES=1: how long each part took, on stderr
let times_on : Bool = @sys.getenv("DETLINT_TIMES") is Some(_)

///|
let lap_t : Ref[UInt64] = { val: @env.now() }

///|
fn lap(what : String) -> Unit {
  if times_on {
    let t = @env.now()
    @sys.eprintln("detlint: \{what} \{(t - lap_t.val).to_string()} ms")
    lap_t.val = t
  }
}

///|
let lex_ms : Ref[UInt64] = { val: 0 }

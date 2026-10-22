// A real host's run (MBUI_TEXT_RECORD=1 MBUI_DRAW_LOG=1: TEXTREC, DRAWHASH, INPUT and ENV lines on its log) made a
// test of whether a Tester over the host's kept text draws, frame for frame, what the host drew (the host's contract,
// docs/determinism.md): the run kept as src/kitdemo/gallery/textrec_NAME.mbt, its test
// src/kitdemo/gallery/textrec_NAME_wbtest.mbt, and src/kitdemo/gallery/textrec_runs.mbt naming every kept run (what
// MBUI_TEXTCHECK=NAME asks the host's text system again: the text's contract, src/kitdemo/gallery/textcheck.mbt).
//
//     chk textrec [--keep] LOG NAME PAGE W H [PLATFORM]   --keep: listed in textrec_runs.txt (to be committed)
//     chk textrec --runs     textrec_runs.mbt made again from textrec_runs.txt
//     chk textrec --check    CI: textrec_runs.mbt, the list and the runs git keeps agree
//
// W H "-": the window's size at the run's first frame (its DRAWHASH line). PLATFORM is the host's as
// @hostapi.platform has it (0 macOS, 1 iOS, 2 Android, 3 Windows, 4 the web; 0 by default).

///|
fn kit() -> String {
  @sys.join(root(), "src/kitdemo/gallery")
}

///|
/// The runs kept in the repository: textrec_runs.txt, a name a line (an explicit list, not whatever textrec_*.mbt a
/// working directory happens to hold: a CI run's own ci_HOST, another machine's leftovers)
fn kept_names() -> Array[String] {
  let text = match @sys.read_text(@sys.join(kit(), "textrec_runs.txt")) {
    Some(t) => t
    None => return []
  }
  let set : Map[String, Unit] = Map::new()
  for l in text_lines(text) {
    let s = trim(l)
    if s != "" && !l.has_prefix("#") {
      set[s] = ()
    }
  }
  let names = set.keys().collect()
  names.sort_by(@rjson.str_cmp)
  names
}

///|
/// A text's lines as Python's text mode reads them (\r\n and \r are \n), the last one's end not making another
fn text_lines(text : String) -> Array[String] {
  let t = text.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
  let out = t.split("\n").map(fn(l) { l.to_string() }).to_array()
  if out.length() > 0 && out[out.length() - 1] == "" {
    let _ = out.pop()
  }
  out
}

///|
fn runs_text(names : Array[String]) -> String {
  let out = [
    "// Every run kept in this package (textrec_NAME.mbt, listed in textrec_runs.txt), by its name: what",
    "// MBUI_TEXTCHECK=NAME asks the host's text system again (textcheck.mbt). Made by scripts/chk textrec: not",
    "// edited by hand.", "", "///|", "fn kept_run(name : String) -> String? {", "  match name {",
  ]
  for n in names {
    out.push("    \"\{n}\" => Some(run_\{n})")
  }
  out.append(["    _ => None", "  }", "}"])
  out.join("\n") + "\n"
}

///|
/// textrec_runs.mbt from the list, `add` put in the list first (a run kept to be committed)
fn runs_file(add : String?) -> Unit {
  let mut names = kept_names()
  match add {
    Some(a) if !names.contains(a) => {
      names = names + [a]
      names.sort_by(@rjson.str_cmp)
      let head = "# The runs kept in src/kitdemo (textrec_NAME.mbt), a name a line: scripts/chk textrec --keep adds one.\n"
      let _ = @sys.write_text(
        @sys.join(kit(), "textrec_runs.txt"),
        head + names.map(fn(n) { n + "\n" }).join(""),
      )
    }
    _ => ()
  }
  let _ = @sys.write_text(@sys.join(kit(), "textrec_runs.mbt"), runs_text(names))
}

///|
/// CI: textrec_runs.mbt is what the list makes, each listed run's files are there, and (in a git checkout) each run
/// git keeps is listed. Fails saying which
fn textrec_check() -> Int {
  let faults = []
  let names = kept_names()
  if @sys.read_text(@sys.join(kit(), "textrec_runs.mbt")) != Some(runs_text(names)) {
    faults.push(
      "src/kitdemo/gallery/textrec_runs.mbt is not what textrec_runs.txt makes (scripts/chk textrec --runs)",
    )
  }
  for n in names {
    for f in ["textrec_\{n}.mbt", "textrec_\{n}_wbtest.mbt"] {
      if !@sys.exists(@sys.join(kit(), f)) {
        faults.push(
          "textrec_runs.txt lists \{n}, but src/kitdemo/gallery/\{f} is not there",
        )
      }
    }
  }
  let r = root()
  match @sys.run_out("git -C '\{r}' ls-files 'src/kitdemo/gallery/textrec_*.mbt'") {
    Some(out) =>
      for f in out.split("\n") {
        let f = trim(f.to_string())
        if f == "" {
          continue
        }
        let b = @sys.basename(f)
        if b.has_suffix("_wbtest.mbt") || b == "textrec_runs.mbt" {
          continue
        }
        let n = b
          .view(start_offset="textrec_".length(), end_offset=b.length() - ".mbt".length())
          .to_string()
        if !names.contains(n) {
          faults.push("\{f} is kept in git but not listed in textrec_runs.txt")
        }
      }
    None => ()
  }
  for f in faults {
    say("textrec runs: " + f)
  }
  if faults.length() > 0 {
    1
  } else {
    0
  }
}

///|
/// A number of the log as a MoonBit Double literal
fn num(x : String) -> String {
  if x.contains(".") || x.contains("e") || x.contains("inf") {
    x
  } else {
    x + ".0"
  }
}

///|
/// From w's first place in l on
fn tail(l : String, w : String) -> String {
  match l.find(w) {
    Some(k) => l.view(start_offset=k).to_string()
    None => l
  }
}

///|
let env_line : @re.Regex = rx("(^|[\\s:])(ENV \\{.*)")

///|
/// The host's frames, the inputs between them and the system's settings (ENV), as they came
fn frame_line(l : String) -> String? {
  if l.contains("TEXTREC ") {
    return None
  }
  for w in ["DRAWHASH ", "INPUT "] {
    if l.contains(w) {
      return Some(tail(l, w))
    }
  }
  match env_line.search(l) {
    Some(m) => Some(m.get(2))
    None => None
  }
}

///|
fn split_ws(s : String) -> Array[String] {
  let out = []
  let cur = StringBuilder::new()
  let mut any = false
  for ch in s {
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '\u{b}' || ch == '\u{c}' {
      if any {
        out.push(cur.to_string())
        cur.reset()
        any = false
      }
    } else {
      cur.write_char(ch)
      any = true
    }
  }
  if any {
    out.push(cur.to_string())
  }
  out
}

///|
fn textrec(args : Array[String]) -> Int {
  let keep_it = args.contains("--keep")
  let args = args.filter(fn(a) { a != "--keep" })
  if args == ["--runs"] {
    runs_file(None)
    return 0
  }
  if args == ["--check"] {
    return textrec_check()
  }
  if args.length() < 5 {
    @sys.eprintln("chk textrec [--keep] LOG NAME PAGE W H [PLATFORM] | --runs | --check")
    return 2
  }
  let log = args[0]
  let name = args[1]
  let page = args[2]
  let mut w = args[3]
  let mut h = args[4]
  let platform = if args.length() > 5 { args[5] } else { "0" }
  let lines = text_lines(@sys.read_text(log).unwrap_or(""))
  let first = match lines.search_by(fn(l) { l.contains("DRAWHASH ") }) {
    Some(i) => split_ws(tail(lines[i], "DRAWHASH"))
    None => {
      @sys.eprintln("chk textrec: no DRAWHASH line in \{log}")
      return 1
    }
  }
  let t0 = first[2]
  let scale = first[5]
  let stable = if first.length() > 7 && first[7] == "1" { "true" } else { "false" }
  if w == "-" {
    w = first[3]
    h = first[4]
  }
  let size = "\{w}x\{h}"
  let w = num(w)
  let h = num(h)
  let scale = num(scale)
  let t0 = num(t0)
  let keep = lines.filter(fn(l) { l.contains("TEXTREC ") }).map(fn(l) { tail(l, "TEXTREC") })
  for l in lines {
    match frame_line(l) {
      Some(k) => keep.push(k)
      None => ()
    }
  }
  let how = "\{name}: MBUI_TEXT_RECORD=1 MBUI_DRAW_LOG=1 MBUI_SCREEN=\{page} MBUI_WIN=\{size}, platform \{platform}"
  let data = [
    "// Kept from a real host's run (\{how}),", "// made by scripts/chk textrec: not edited by hand.",
    "", "///|", "let run_\{name} : String =",
  ]
  for l in keep {
    data.push("  #|" + l)
  }
  let plat = if platform != "0" { ", platform=\{platform}" } else { "" }
  let wbtest = [
    "// A Tester over \{name}'s kept text and frames (textrec_\{name}.mbt), made by scripts/chk textrec.",
    "",
    "///|",
    "test \"the \{page} page under a Tester over \{name}'s kept text draws, frame for frame, what it drew\" {",
    "  reset()",
    "  let t = @ui.Tester::new(fn(c) { gallery(c, \"\{page}\") }, w=\{w}, h=\{h}, text=run_\{name}, run=run_\{name}, scale=\{scale}, time=\{t0} - 16.0, stable=\{stable}\{plat})",
    "  let frames = t.replay_frames(run_\{name})",
    "  let apart = frames.filter(fn(f) { f.1 != f.2 })",
    "  println(\"frames \\{frames.length()}, apart \\{apart.length()}, text missing \\{t.text_missing()}\")",
    "  if apart.length() > 0 {",
    "    println(\"first apart: frame \\{apart[0].0}\")",
    "    for line in t.drawn_text().split(\"\\n\") {",
    "      println(\"TDUMP \" + line.to_owned())",
    "    }",
    "  }",
    "  assert_true(frames.length() > 0)",
    "  assert_eq(t.text_missing(), [])",
    "  assert_eq(apart.length(), 0)",
    "}",
  ]
  let _ = @sys.write_text(
    @sys.join(kit(), "textrec_\{name}.mbt"),
    data.join("\n") + "\n",
  )
  let _ = @sys.write_text(
    @sys.join(kit(), "textrec_\{name}_wbtest.mbt"),
    wbtest.join("\n") + "\n",
  )
  runs_file(if keep_it { Some(name) } else { None })
  say("\{keep.length()} lines")
  0
}

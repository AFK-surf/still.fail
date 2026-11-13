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
  /// what draws a look not the theme's (detlint.json `style.outside`): no style rule counts it
  style_outside : Array[String]
  // what tells outside of a frame: field calls ((src.call)(…): their field's name) and package functions
  effect_fields : Array[String]
  effect_calls : Array[String]
  effect_methods : Array[String]
  // package functions that keep what they are given and run it later, never as they are called (an app's presenters:
  // @sf.confirm(…, fn() { … })): a closure given to one is a callback
  effect_later : Array[String]
  // an app's component library (web/ui's): its packages, and what they may import (prefixes); nothing else of the app
  library : Array[String]
  library_imports : Array[String]
  // an app's pages: where the current input (@ui.pointing()) is never read (page-hand), nor the native input (page-screen)
  pages : Array[String]
  // what of one arrangement a page may not draw itself (page-look): names (a style's, a part's, a branch's), and the
  // files that frame the pages and name those pieces for them (not counted)
  one_look : Array[String]
  page_frames : Array[String]
  // the parts a page used to take from an older copy (`@settings.button`, …), the library's now (page-old-part)
  old_parts : Array[String]
  // the shell's files among the pages' roots: what lays the panes out by the tier (`shell.files`), the only ones that
  // read it or the shell's own state (tier-outside-shell): the calls that do (`shell.reads`: `@sf.layout`, `is_wide`,
  // …) and the shell's state read by its fields (`shell.state`: `wide.tape`, …); nor are they pages to page-screen
  shell : Array[String]
  shell_reads : Array[String]
  shell_state : Array[String]
  // what puts a sheet up in an older host of its own (the settings' `open_sheet`, a chat's), not the library's
  // presenters (page-old-sheet)
  old_sheets : Array[String]
  // the made-up core (`fixture.package`, `@sffixture`): only the files that open a mode over the app
  // (`fixture.openers`) say it, of the app's pages and its library, outside their tests (fixture-import)
  fixture_pkg : String
  fixture_openers : Array[String]
  // what only a Tester sets, read by what runs in the app (`tester.names`: `fake`, read as `fake.val`), outside the
  // Tester's own files (`tester.files`, globs) and the tests (tester-branch)
  tester_names : Array[String]
  tester_files : Array[String]
  // what starts a test's own run of the app (`run_first.starts`: the app's new_run; `@pkg.name` or a bare name) and
  // what reads the app's words or language (`run_first.reads`): in a test file, none of the second before the first
  // (read-before-run)
  run_starts : Array[String]
  run_reads : Array[String]
  // what puts the app back by hand before the Tester a test makes (`reset_by_hand.names`: the app's new_run): in a test
  // file, a Tester made after it in the same test or function (reset-by-hand)
  reset_by_hand : Array[String]
  // what names an app built on this module (`app_words`: regular expressions), found outside comments (app-word)
  app_words : Array[String]
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
    style_outside: strs(sect(d, "style").get("outside"), []),
    effect_fields: strs(be.get("fields"), ["call", "subscribe"]),
    effect_calls: strs(be.get("calls"), build_effect_calls),
    effect_methods: strs(be.get("methods"), build_effect_methods),
    effect_later: strs(be.get("later"), []),
    library: strs(sect(d, "library").get("roots"), []),
    library_imports: strs(sect(d, "library").get("imports"), ["mbui/", "moonbitlang/"]),
    pages: strs(sect(d, "pages").get("roots"), []),
    one_look: strs(sect(d, "pages").get("one_look"), []),
    page_frames: strs(sect(d, "pages").get("frames"), []),
    old_parts: strs(sect(d, "pages").get("old_parts"), []),
    old_sheets: strs(sect(d, "pages").get("old_sheets"), []),
    shell: strs(sect(d, "shell").get("files"), []),
    shell_reads: strs(sect(d, "shell").get("reads"), []),
    shell_state: strs(sect(d, "shell").get("state"), []),
    fixture_pkg: match sect(d, "fixture").get("package") {
      Some(Str(s)) => s
      _ => ""
    },
    fixture_openers: strs(sect(d, "fixture").get("openers"), []),
    tester_names: strs(sect(d, "tester").get("names"), []),
    tester_files: strs(sect(d, "tester").get("files"), []),
    run_starts: strs(sect(d, "run_first").get("starts"), []),
    run_reads: strs(sect(d, "run_first").get("reads"), []),
    reset_by_hand: strs(sect(d, "reset_by_hand").get("names"), []),
    app_words: strs(d.get("app_words"), []),
  }
}

///|
fn Config::host_dirs(self : Config) -> Array[String] {
  self.framework.filter(fn(p) {
    let q = if p.has_suffix("/") {
      p.exact_view(end=p.length() - 1).to_owned()
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
  parts[parts.length() - 1].to_owned()
}

///|
fn lint_mbt(
  f : MbtFile,
  cfg : Config,
  out : Array[Finding],
  returns : Map[String, String],
  readers : Map[String, String],
  painted : Map[String, Unit],
  motion_fields : Map[String, Unit],
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

  // corners not all alike said, in the app's pages and its library (Radius::Corners, LinkedEach): a design's, each
  // looked at and kept by a person, never made by the way; counted, so a new one is seen (its tests not counted)
  if under(f.rel, cfg.pages) || under(f.rel, cfg.library) {
    for k, tk in toks {
      if tk.kind == "ident" &&
        (tk.text == "Corners" || tk.text == "LinkedEach") &&
        k + 1 < toks.length() &&
        toks[k + 1].text == "(" &&
        !f.in_test(k) {
        add("corners-each", k, f.line_text(k))
      }
    }
  }
  // a page drawing one arrangement's piece itself (not in its tests, nor in the files that frame the pages)
  if under(f.rel, cfg.pages) && !under(f.rel, cfg.page_frames) && cfg.one_look.length() > 0 {
    for k, tk in toks {
      if tk.kind == "ident" && cfg.one_look.contains(tk.text) && !f.in_test(k) {
        add("page-look", k, f.line_text(k))
      }
    }
  }
  // the made-up core said by the app (its pages, its library), not in a file that opens a mode over the app nor a test
  if cfg.fixture_pkg != "" &&
    (under(f.rel, cfg.pages) || under(f.rel, cfg.library)) &&
    !under(f.rel, cfg.fixture_openers) {
    for k, tk in toks {
      if tk.kind == "at" && tk.text == cfg.fixture_pkg && !f.in_test(k) {
        add("fixture-import", k, f.line_text(k))
      }
    }
  }
  // what only a Tester sets read by what runs in the app (`fake.val`), outside the Tester's own files and the tests
  if cfg.tester_names.length() > 0 && !matches(f.rel, cfg.tester_files) {
    for k, tk in toks {
      if tk.kind == "ident" &&
        cfg.tester_names.contains(tk.text) &&
        !(k > 0 && toks[k - 1].text == ".") &&
        k + 2 < toks.length() &&
        toks[k + 1].text == "." &&
        toks[k + 2].text == "val" &&
        !f.in_test(k) {
        add("tester-branch", k, f.line_text(k))
      }
    }
  }
  // a frame's or a build's number asked (`c.frame_number()`, `c.build_number()`) outside mbui's ui, which counts them,
  // and outside the tests
  if !f.rel.has_prefix("src/ui/") {
    for k, tk in toks {
      if tk.kind == "ident" &&
        (tk.text == "frame_number" || tk.text == "build_number") &&
        k > 0 &&
        toks[k - 1].text == "." &&
        k + 1 < toks.length() &&
        toks[k + 1].text == "(" &&
        !f.in_test(k) {
        add("frame-number", k, f.line_text(k))
      }
    }
  }
  // the frames' clock read followed by its own signal (`frame_clock.get()`), outside the tests and what paints
  // (build-clock)
  let paint_at = paint_flows(f, paint_args(f))
  let painting = fn(k : Int) { in_paint(f, k, paint_at, painted) }
  for k, tk in toks {
    if tk.kind == "ident" &&
      tk.text == "frame_clock" &&
      k + 2 < toks.length() &&
      toks[k + 1].text == "." &&
      toks[k + 2].text == "get" &&
      !f.in_test(k) &&
      !painting(k) {
      add("build-clock", k, f.line_text(k))
    }
  }
  // a part of the app's component library made in a node it is given (its first parameter a @view.View it makes a box
  // in) that takes no place of its caller's (`loc~ : SourceLoc`, its outside made as what was asked for there,
  // `made_for=loc`): what is found in it is not traced back to the app's line that asked for it (view's source.mbt)
  if under(f.rel, cfg.library) && !f.test_file {
    for it in f.items {
      if it.kind != "fn" {
        continue
      }
      // (its parameters: the first bracket after its name)
      let mut open = it.start
      while open <= it.end && toks[open].text != "(" {
        open += 1
      }
      if open > it.end || toks[open].end < 0 || open + 5 > it.end {
        continue
      }
      let close = toks[open].end
      let name = toks[open + 1]
      let given = name.kind == "ident" &&
        toks[open + 2].text == ":" &&
        toks[open + 3].text == "@view" &&
        toks[open + 4].text == "." &&
        toks[open + 5].text == "View" &&
        (toks[open + 6].text == "," || toks[open + 6].text == ")")
      if !given {
        continue
      }
      let mut placed = false
      for k in open..<close {
        if toks[k].kind == "ident" && toks[k].text == "SourceLoc" {
          placed = true
        }
      }
      let mut boxed = false
      for k in (close + 1)..<(it.end - 2) {
        if toks[k].kind == "ident" &&
          toks[k].text == name.text &&
          toks[k + 1].text == "." &&
          toks[k + 2].text == "box" &&
          toks[k + 3].text == "(" {
          boxed = true
          break
        }
      }
      if boxed && !placed {
        add("part-place", it.start, f.line_text(it.start))
      }
    }
  }
  // a click read by a build (`c.clicked(id)`, `clicked_on`, `double_clicked`: a Bool the frame after it) outside mbui's
  // ui and kit, which take presses, and outside the tests: what a press does is its handler's (Ctx::on_press, a part's
  // on_press / on_pick / on_change)
  if !f.rel.has_prefix("src/ui/") && !f.rel.has_prefix("src/kit/") {
    for k, tk in toks {
      if tk.kind == "ident" &&
        (tk.text == "clicked" || tk.text == "clicked_on" || tk.text == "double_clicked") &&
        k > 0 &&
        toks[k - 1].text == "." &&
        k + 1 < toks.length() &&
        toks[k + 1].text == "(" &&
        !f.in_test(k) {
        add("click-read", k, f.line_text(k))
      }
    }
  }
  // an empty `on_done` (or `done` of a source's call: `(src.call)(name, params, fn(_) {  })`) outside the tests: to the
  // core it is a reader, its answer awaited and the frame after it built whole for nothing; a call nobody reads the
  // answer of gives none (@core.call) or the app's answer_unread (still.fail's sfbase/source.mbt); so a native call's
  // empty `on_got` (@ui.native_call: none given, nobody reads its answer)
  for k, tk in toks {
    if tk.text == "fn" &&
      k + 5 < toks.length() &&
      toks[k + 1].text == "(" &&
      toks[k + 2].text == "_" &&
      toks[k + 3].text == ")" &&
      toks[k + 4].text == "{" &&
      toks[k + 5].text == "}" &&
      k > 1 &&
      !f.in_test(k) &&
      (
        (toks[k - 1].text == "=" && (toks[k - 2].text == "on_done" || toks[k - 2].text == "on_got")) ||
        (toks[k - 1].text == "," &&
        k + 6 < toks.length() &&
        toks[k + 6].text == ")" &&
        done_of_call(toks, k))
      ) {
      add("empty-on-done", k, f.line_text(k))
    }
  }
  // a key read by a build (`c.key_pressed(code)`, `c.keys_came()`, `@settings.action_pressed(…)`: a Bool the frame
  // after it) outside mbui's ui and kit, which take keys, and outside the tests: what a key does is an action's
  // (View::on_action) or a node's own (View::on_key)
  if !f.rel.has_prefix("src/ui/") && !f.rel.has_prefix("src/kit/") {
    for k, tk in toks {
      if tk.kind == "ident" &&
        (tk.text == "key_pressed" || tk.text == "keys_came" || tk.text == "action_pressed") &&
        k > 0 &&
        toks[k - 1].text == "." &&
        k + 1 < toks.length() &&
        toks[k + 1].text == "(" &&
        !f.in_test(k) {
        add("key-read", k, f.line_text(k))
      }
    }
  }
  // a page reading the shell's own state by its fields (`wide.tape`): the shell's files alone do (not in a page's tests)
  if under(f.rel, cfg.pages) && !under(f.rel, cfg.shell) && cfg.shell_state.length() > 0 {
    for k, tk in toks {
      if tk.kind == "ident" &&
        cfg.shell_state.contains(tk.text) &&
        k + 1 < toks.length() &&
        toks[k + 1].text == "." &&
        !(k > 0 && toks[k - 1].text == ".") &&
        !f.in_test(k) {
        add("tier-outside-shell", k, f.line_text(k))
      }
    }
  }
  // a test that passes by stopping its program (`test "panic …"`, moon's own way): what runs after it in the process
  // begins where it stopped
  for it in f.items {
    if it.kind == "test" && it.name.has_prefix("panic") {
      add("panic-test", it.start, f.line_text(it.start))
    }
  }
  // a page putting a sheet up in an older host of its own (not in its tests; the host's own `fn` not counted)
  if under(f.rel, cfg.pages) && cfg.old_sheets.length() > 0 {
    for k, tk in toks {
      if tk.kind == "ident" &&
        cfg.old_sheets.contains(tk.text) &&
        !f.in_test(k) &&
        !(k > 0 && toks[k - 1].text == "fn") &&
        k + 1 < toks.length() &&
        toks[k + 1].text == "(" {
        add("page-old-sheet", k, f.line_text(k))
      }
    }
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
    // an abort of its own, in a test too: on wasm-gc its words are never printed (@halt.saying prints them first)
    if c.name == "abort" &&
      (c.kind == "bare" || (c.kind == "pkg" && c.qual == "@builtin")) {
      add("abort-unsaid", c.at, f.line_text(c.at))
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
    // a page reading the hand (its tests may say which hand they are)
    if c.name == "pointing" && c.kind == "pkg" && c.qual == "@ui" && !in_t && under(f.rel, cfg.pages) {
      add("page-hand", c.at, f.line_text(c.at))
    }
    // the frame's context reached from anywhere (`@ui.current()`): outside mbui's ui, which keeps it, and the tests
    if c.name == "current" && c.kind == "pkg" && c.qual == "@ui" && !in_t && !f.rel.has_prefix("src/ui/") {
      add("ui-current", c.at, f.line_text(c.at))
    }
    // a long list laid out by the old immediate-mode view (`c.list(key, count, est, row)`): what is left of it, which
    // only goes (a method of that name with fewer than four arguments, a Markdown writer's, not counted)
    if c.name == "list" && c.kind == "method" && app && !in_t && c.args.length() >= 4 {
      add("old-list", c.at, f.line_text(c.at))
    }
    // a page's list said at once (View::scrolls_window's `at_once=true`): its keys there and gone at once, what its
    // blocks hold each its own way, none of it the list's one way: a debt of 方案 A each list leaves one at a time,
    // shown to the owner, which only goes
    if c.name == "scrolls_window" &&
      c.kind == "method" &&
      app &&
      !in_t &&
      c.args.iter().any(fn(a) { a.0 == Some("at_once") && a.1.map(fn(i) { f.toks[i].text }).join("") == "true" }) {
      add("list-comes-off", c.at, f.line_text(c.at))
    }
    // an old view hosted in a node of the window's tree (`@ui.old(v, build)`): what of the old view is left inside
    // what is made once, waiting for its part as nodes, which only goes
    if c.name == "old" && c.kind == "pkg" && c.qual == "@ui" && app && !in_t {
      add("old-island", c.at, f.line_text(c.at))
    }
    // a panel presented with an old body (`@sf.panel(title, body, ...)`): what is left of them, which only goes
    if c.name == "panel" && c.kind == "pkg" && c.qual == "@sf" && app && !in_t {
      add("old-panel", c.at, f.line_text(c.at))
    }
    // a page reading the native input (what the app was started with: touch, or keyboard and mouse)
    if c.name == "native_input" &&
      c.kind == "pkg" &&
      c.qual == "@sf" &&
      !in_t &&
      under(f.rel, cfg.pages) &&
      !under(f.rel, cfg.shell) {
      add("page-screen", c.at, f.line_text(c.at))
    }
    // a page reading the tier, or asking what the shell lays out by (`@sf.layout`, `is_wide`): the shell's files alone
    // do (its tests may say which tier they are)
    if (c.kind == "pkg" || c.kind == "bare") &&
      cfg.shell_reads.contains(if c.kind == "pkg" { c.qual + "." + c.name } else { c.name }) &&
      !in_t &&
      under(f.rel, cfg.pages) &&
      !under(f.rel, cfg.shell) {
      add("tier-outside-shell", c.at, f.line_text(c.at))
    }
    // a page taking a part from the settings' older copy where the library has the one
    if c.kind == "pkg" && c.qual == "@settings" && cfg.old_parts.contains(c.name) && !in_t && under(f.rel, cfg.pages) {
      add("page-old-part", c.at, f.line_text(c.at))
    }
    // the pointer's hand said: it is what takes presses that shows it (its click read), by itself
    if c.name == "cursor" &&
      c.kind == "method" &&
      !in_t &&
      c.args.length() == 2 &&
      c.args[1].1.iter().any(fn(i) { toks[i].kind == "ident" && toks[i].text == "Hand" }) {
      add("cursor-hand", c.at, f.line_text(c.at))
    }
    // what was built said by hand to be built again: what changed is a signal, and what read it is built again by
    // itself; the framework's own not counted
    if built_by_hand.contains(c.name) && c.kind == "method" && app && !in_t {
      add("built-by-hand", c.at, f.line_text(c.at))
    }
    // where or how large something was laid out, read back by what builds (a first frame has none, a change lays the
    // frame out twice): said as layout instead; the framework's own not counted
    if layout_read_back.contains(c.name) && c.kind == "method" && app && !in_t {
      add("layout-read-back", c.at, f.line_text(c.at))
    }
    // what the layout came to told back as a change to make things by: the framework's (the view's own, src/view, as
    // what it lays out) not counted, its tests not
    if layout_told.contains(c.name) &&
      !layout_told_handlers.contains(c.name) &&
      c.kind == "method" &&
      !under(f.rel, ["src/view"]) &&
      !in_t {
      add("layout-told", c.at, f.line_text(c.at))
    }
    // a motion following what the layout measured: a place or a size moves for its cause, not because what it was
    // laid out at changed (the app's sf/motion.mbt)
    match follow_target(f, c, returns) {
      Some(n) if !in_t => {
        let pos = c.args.filter(fn(a) { a.0 is None })
        if n < pos.length() {
          match reads_layout(f, pos[n].1, item) {
            Some(q) => add("follow-layout", c.at, "\{f.line_text(c.at)}   (follows: \{q})")
            None => ()
          }
        }
      }
      _ => ()
    }
    // whether a motion runs, read by the app: what is shown, what takes a press, when state goes follow from the
    // cause and the motion's declared end (what only draws by it says so on its line, det-ok)
    if c.name == "moving" &&
      c.kind == "method" &&
      c.args.length() == 0 &&
      app &&
      !in_t &&
      !(f.recv_type(c.at, returns) is Some("Tester")) &&
      !moving_listed(f, c.at) {
      add("motion-read", c.at, f.line_text(c.at))
    }
    // a spring of the app's own: each is one of @motion's (the app's sf/motion.mbt, Curves)
    if (c.name == "spring" || c.name == "motion_spring") &&
      app &&
      !in_t &&
      ((c.kind == "pkg" && c.qual == "@motion") || c.kind == "method") {
      add("motion-spring", c.at, f.line_text(c.at))
    }
    // a move of a length of its own: a thing moved takes as long as its way is far (the app's sf/motion.mbt, Curves)
    if c.name == "tween" &&
      !in_t &&
      ((c.kind == "pkg" && c.qual == "@motion") || c.kind == "bare") &&
      c.args.iter().any(fn(a) {
        a.0 == Some("ease") && a.1.length() > 0 && f.toks[a.1[a.1.length() - 1]].text == "Move"
      }) {
      add("motion-length", c.at, f.line_text(c.at))
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
    // the frames' clock read followed (build-clock): a Ctx's (`now` and `cycle` on a Ctx, or on `c`/`ctx` whose type
    // is not told), a motion's (`now_before`, `now_of`, `shows_motion`), ui's own (clock_read, clock_read_here); not
    // in the tests
    if !in_t && build_clock_read(f, c, returns) && !painting(c.at) {
      add("build-clock", c.at, f.line_text(c.at))
    }
    // an animated value read as it is built (build-motion): @motion.animate's, an Anim's, a Way's read (`get`)
    // outside what a frame's paint is given; not in the tests, nor in the readers themselves
    if !in_t && motion_read_built(f, c, returns, motion_fields) && !painting(c.at) {
      add("build-motion", c.at, f.line_text(c.at))
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
/// style-literal, box-loose, style-exact (mbui's ui/style.mbt): tests are not counted
fn lint_style(f : MbtFile, cfg : Config, out : Array[Finding]) -> Unit {
  if matches(f.rel, cfg.style_outside) {
    return
  }
  let toks = f.toks
  let tokens_file = matches(f.rel, cfg.style_tokens)
  let counted : Map[Int, Unit] = Map([])
  fn add(rule : String, k : Int, what : String) {
    out.push(finding(rule, f.rel, toks[k].line, what))
  }

  // each closing bracket's opening one (a pattern's groups stepped over whole, either way)
  let opened : Map[Int, Int] = Map([])
  for i, t in toks {
    if t.end >= 0 {
      opened[t.end] = i
    }
  }
  // the bracket that holds token `i` (-1: none)
  fn holder(i : Int) -> Int {
    let mut j = i - 1
    while j >= 0 {
      if toks[j].end > i {
        return j
      }
      j = match opened.get(j) {
        Some(o) => o - 1
        None => j - 1
      }
    }
    -1
  }

  // what a pattern is made of besides its groups: names (a constructor's, a binding's, `_`, a package's), literals, an
  // or-pattern's |, a tuple's or a constructor's commas
  fn in_pattern(t : Tok) -> Bool {
    (t.kind == "ident" && t.text != "if" && t.text != "return") ||
    t.kind == "at" ||
    t.kind == "num" ||
    t.kind == "str" ||
    t.text == "|" ||
    t.text == "," ||
    t.text == "." ||
    t.text == "::" ||
    t.text == "-"
  }

  // an Exact(…) made (not the enum's own declaration, nor a match arm's pattern: what is left of an arm's =>, before its
  // guard's if, the groups it is in included; one in a guard or in what the arm gives is made)
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
    // (the whole of what it is in, up to the braces it is said in: Some(Exact(v)), (S4, Exact(v)))
    let mut s = k
    let mut e = toks[k + 1].end
    while true {
      let h = holder(s)
      if h < 0 || !(toks[h].text == "(" || toks[h].text == "[") {
        break
      }
      s = h
      e = toks[h].end
      // (its constructor's name before it, on its line: not what ends the arm before)
      while s > 0 &&
            toks[s - 1].line == toks[s].line &&
            (toks[s - 1].kind == "ident" || toks[s - 1].kind == "at" || toks[s - 1].text == ".") {
        s = s - 1
      }
    }
    guard e >= 0 else { return true }
    // (back to where its arm begins: a line begun, or the braces opened, over nothing but a pattern's)
    let mut j = s - 1
    let mut head = false
    while j >= 0 {
      let t = toks[j]
      let broken = toks[j + 1].line > t.line && t.text != "|" && t.text != ","
      if broken || t.text == "{" {
        head = true
        break
      }
      match opened.get(j) {
        Some(o) => j = o - 1
        None => {
          if !in_pattern(t) {
            break
          }
          j = j - 1
        }
      }
    }
    guard head || j < 0 else { return true }
    // (on to the arm's => or its guard's if, over nothing but a pattern's, a line broken only after | or ,)
    let mut n = e + 1
    while n < toks.length() {
      let t = toks[n]
      if t.text == "=>" || (t.kind == "ident" && t.text == "if") {
        return false
      }
      if t.line > toks[n - 1].line && toks[n - 1].text != "|" && toks[n - 1].text != "," {
        return true
      }
      if t.end >= 0 {
        n = t.end + 1
      } else if in_pattern(t) {
        n = n + 1
      } else {
        return true
      }
    }
    true
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
  // a style said as text (@ui.css("w=Grow(1.0) radius=Exact(9.0)")): what is in it counts as it does in style(…),
  // each Exact(…) once (its numbers not again), each other number once
  for c in f.calls {
    if c.is_def ||
      f.in_test(c.at) ||
      c.name != "css" ||
      !((c.kind == "pkg" && c.qual == "@ui") || c.kind == "bare") {
      continue
    }
    for a in c.args {
      for i in a.1 {
        if toks[i].kind == "str" {
          for what in css_literals(toks[i].text) {
            if what == "Exact" {
              add("style-exact", i, f.line_text(c.at))
            }
            if !tokens_file {
              add("style-literal", i, f.line_text(c.at))
            }
          }
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
/// What a style's text says off the scale: "Exact" for each Exact(…) (what is in its parentheses not again), "num"
/// for each other number (one that starts after no name's letter or digit: not S1_25's, O35's).
fn css_literals(text : String) -> Array[String] {
  let out = []
  let s = text.to_array()
  let n = s.length()
  fn word(c : Char) -> Bool {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '.'
  }
  let mut i = 0
  while i < n {
    let c = s[i]
    let after_word = i > 0 && word(s[i - 1])
    if c == 'E' &&
      !after_word &&
      i + 5 < n &&
      s[i + 1] == 'x' &&
      s[i + 2] == 'a' &&
      s[i + 3] == 'c' &&
      s[i + 4] == 't' &&
      s[i + 5] == '(' {
      out.push("Exact")
      let mut depth = 0
      i += 5
      while i < n {
        if s[i] == '(' {
          depth += 1
        } else if s[i] == ')' {
          depth -= 1
          if depth == 0 {
            break
          }
        }
        i += 1
      }
    } else if c >= '0' && c <= '9' && !after_word {
      out.push("num")
      while i + 1 < n && word(s[i + 1]) {
        i += 1
      }
    }
    i += 1
  }
  out
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
  let skip : Map[Int, Unit] = Map([])
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
/// Which positional argument of call `c` is the target a motion follows: an Anim's `follow(target, …)`,
/// `@motion.animate(c, key, target)`, `Ctx::spring(key, target)`; None for any other call.
fn follow_target(f : MbtFile, c : Call, returns : Map[String, String]) -> Int? {
  if c.kind == "method" && c.name == "follow" {
    Some(0)
  } else if c.kind == "pkg" && c.name == "animate" && c.qual == "@motion" {
    Some(2)
  } else if c.kind == "method" && c.name == "spring" && f.recv_type(c.at, returns) is Some("Ctx") {
    Some(1)
  } else {
    None
  }
}

///|
/// Whether the `moving()` at `k` is a Tester's list of what moves (`for m in t.moving()`, `t.moving().iter()`), not
/// whether a motion runs.
fn moving_listed(f : MbtFile, k : Int) -> Bool {
  let toks = f.toks
  // its call's closing bracket, and what follows it
  let o = k + 1
  if o < toks.length() && toks[o].text == "(" && toks[o].end >= 0 {
    let after = toks[o].end + 1
    if after < toks.length() && toks[after].text == "." {
      return true
    }
  }
  // `in` before its receiver (a chain of names and dots)
  let mut j = k - 1
  while j > 0 && (toks[j].text == "." || toks[j].kind == "ident") {
    j -= 1
  }
  j >= 0 && toks[j].text == "in"
}

///|
/// What the layout measures, as read by a view: a node's size or place, the window's, the keyboard's.
let layout_reads : Array[String] = [
  "measured", "measured_rect", "laid_size", "laid_rect", "laid_out", "rect_of", "node_rect", "drawn_rect",
  "drawn_at", "window_size", "ime_inset", "list_place", "list_row_height", "row_height",
]

///|
/// Whether tokens `idx` (an argument) read what the layout measures: a call of one of layout_reads, or a name bound
/// in the same item (`let x = …`) to what calls one; what it reads, if so.
fn reads_layout(f : MbtFile, idx : Array[Int], item : Int) -> String? {
  let toks = f.toks
  let direct = fn(ii : Array[Int]) -> String? {
    for i in ii {
      let t = toks[i]
      if t.kind == "ident" &&
        i + 1 < toks.length() &&
        toks[i + 1].text == "(" &&
        layout_reads.contains(t.text) {
        return Some(t.text)
      }
    }
    None
  }
  match direct(idx) {
    Some(q) => return Some(q)
    None => ()
  }
  if item < 0 || idx.length() == 0 {
    return None
  }
  let lo = f.items[item].start
  for i in idx {
    let t = toks[i]
    if t.kind != "ident" || (i + 1 < toks.length() && toks[i + 1].text == "(") || (i > 0 && toks[i - 1].text == ".") {
      continue
    }
    // the nearest `let name =` before the argument, its value to the end of its line
    let mut j = idx[0] - 1
    while j > lo {
      let at_let = toks[j].text == t.text &&
        j + 1 < toks.length() &&
        (toks[j + 1].text == "=" || toks[j + 1].text == ":") &&
        (toks[j - 1].text == "let" || (toks[j - 1].text == "mut" && j > 1 && toks[j - 2].text == "let"))
      if at_let {
        let line = toks[j].line
        let rhs : Array[Int] = []
        let mut k = j + 1
        while k < toks.length() && toks[k].line == line {
          rhs.push(k)
          k += 1
        }
        match direct(rhs) {
          Some(q) => return Some(t.text + " = " + q + "()")
          None => ()
        }
        break
      }
      j -= 1
    }
  }
  None
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
        cfg.queries.contains(t.text.exact_view(start=2).to_owned()) {
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
  let bodies : Map[String, (MbtFile, Int, Int)] = Map([])
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
  let readers : Map[String, String] = Map([])
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
  s.trim(chars=" \t\r\n").to_owned()
}

///|
/// 7b: per package under globals.roots, every top-level let of a non-plain type is put back by the package's reset
/// (reset, reset_globals, a function given to on_reset, and what those call) or says why not
fn lint_globals(files : Array[MbtFile], cfg : Config, out : Array[Finding]) -> Unit {
  let pkgs : Map[String, Array[MbtFile]] = Map([])
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
  let pkg_by_name : Map[String, String] = Map([])
  for p, _ in pkgs {
    pkg_by_name[@sys.basename(p)] = p
  }
  let fns : Map[String, Array[Array[Tok]]] = Map([]) // (pkg, name) -> [token lists]
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
        let body = f.toks[it.start:@cmp.minimum(it.end + 1, f.toks.length())].to_owned()
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
  let said : Map[String, Map[String, Unit]] = Map([])
  for p, _ in pkgs {
    said[p] = Map([])
  }
  let seen : Map[String, Unit] = Map([])
  // what reset sets a global's value to (NAME.val = …, its package's, or @pkg.NAME.val = …): (pkg, name, value)
  let sets : Array[(String, String, String)] = []
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
        // NAME.val = VALUE (@pkg.NAME.val = VALUE): what reset sets it to, to its line's end at its own depth
        if i + 3 < body.length() &&
          body[i + 1].text == "." &&
          body[i + 2].text == "val" &&
          body[i + 3].text == "=" &&
          (i == 0 || body[i - 1].text != "." || (i >= 2 && body[i - 2].kind == "at")) {
          let owner = if i >= 2 && body[i - 1].text == "." && body[i - 2].kind == "at" {
            pkg_by_name.get(body[i - 2].text.exact_view(start=1).to_owned())
          } else {
            Some(pkg)
          }
          let value : Array[String] = []
          let mut depth = 0
          let mut k = i + 4
          while k < body.length() {
            let v = body[k]
            if depth == 0 && value.length() > 0 && v.line > body[k - 1].line {
              break
            }
            if v.text == "(" || v.text == "[" || v.text == "{" {
              depth += 1
            } else if v.text == ")" || v.text == "]" || v.text == "}" {
              if depth == 0 {
                break
              }
              depth -= 1
            }
            value.push(v.text)
            k += 1
          }
          // (a wire: what does the work, a function named (f, @pkg.f) or given (fn …); a value put back, made by a
          // call or said, is state, not a wire)
          let wire = value.length() > 0 &&
            (
              value[0] == "fn" ||
              (value.length() == 1 && body[i + 4].kind == "ident" && !["true", "false", "None"].contains(value[0])) ||
              (value.length() == 3 && body[i + 4].kind == "at" && value[1] == ".")
            )
          match owner {
            Some(o) if wire => sets.push((o, t.text, value.join(" ")))
            _ => ()
          }
        }
        if i + 1 < body.length() && body[i + 1].text == "(" {
          let q = if i >= 2 && body[i - 1].text == "." && body[i - 2].kind == "at" {
            Some(body[i - 2].text)
          } else {
            None
          }
          let p = match q {
            Some(q) => pkg_by_name.get(q.exact_view(start=1).to_owned())
            None => Some(pkg)
          }
          if p is Some(p) {
            todo.push((p, t.text))
          }
        }
        if i >= 2 && body[i - 1].text == "." && body[i - 2].kind == "at" {
          match pkg_by_name.get(body[i - 2].text.exact_view(start=1).to_owned()) {
            Some(p) => said[p][t.text] = ()
            None => ()
          }
        }
      }
    }
  }
  // a Ref's value as its let gives it (Ref(V), Ref::new(V), { val: V }), by (pkg, name)
  let firsts : Map[String, (MbtFile, Int, String)] = Map([])
  for l in lets {
    let (pkg, f, it) = l
    let ts = f.toks[it.start:@cmp.minimum(it.end + 1, f.toks.length())].to_owned()
    match ts.search_by(fn(t) { t.text == "=" }) {
      Some(e) => {
        let v = ts[e + 1:].to_owned()
        let inner = if v.length() >= 3 && v[0].text == "Ref" && v[1].text == "(" {
          Some(2)
        } else if v.length() >= 5 && v[0].text == "Ref" && v[1].text == "::" && v[2].text == "new" && v[3].text == "(" {
          Some(4)
        } else if v.length() >= 4 && v[0].text == "{" && v[1].text == "val" && v[2].text == ":" {
          Some(3)
        } else {
          None
        }
        match inner {
          Some(s) => {
            let out : Array[String] = []
            let mut depth = 0
            for t in v[s:] {
              if t.text == "(" || t.text == "[" || t.text == "{" {
                depth += 1
              } else if t.text == ")" || t.text == "]" || t.text == "}" {
                if depth == 0 {
                  break
                }
                depth -= 1
              }
              out.push(t.text)
            }
            let name = match ts.search_by(fn(t) { t.text == "let" }) {
              Some(k) if k + 1 < ts.length() => ts[k + 1].text
              _ => ""
            }
            firsts[reader_key(pkg, name)] = (f, it.line, out.join(" "))
          }
          None => ()
        }
      }
      None => ()
    }
  }
  let wired : Map[String, Unit] = Map([])
  for s in sets {
    let (pkg, name, value) = s
    let key = reader_key(pkg, name)
    match firsts.get(key) {
      Some((f, line, first)) if first != value && !wired.contains(key) => {
        wired[key] = ()
        out.push(finding("reset-wire", f.rel, line, "\{name}: reset sets `\{value}`, its let `\{first}`"))
      }
      _ => ()
    }
  }
  for l in lets {
    let (pkg, f, it) = l
    let ts = f.toks[it.start:@cmp.minimum(it.end + 1, f.toks.length())].to_owned()
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
    let value = if j < ts.length() { ts[j + 1:].to_owned() } else { [] }
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

///|
/// what `style(…)` (and a state's `patch(…)`) says, as its text says it (src/ui/style_css.mbt): every one of them
let css_props : Array[String] = [
  "row", "w", "h", "min_w", "max_w", "min_h", "max_h", "p", "px", "py", "pl", "pr", "pt", "pb", "m", "mx", "my", "ml",
  "mr", "mt", "mb", "gap", "align", "justify", "bg", "radius", "border", "border_color", "shadow", "clip", "opacity",
]

///|
let css_states : Array[String] = [
  "narrow", "dark", "selected", "hovered", "focused", "pressed", "disabled",
]

///|
/// A token's name, not a constant's: a constructor called (`Fixed(`, `A(`), or a name with a small letter (`Full`,
/// `ACenter`, `SPx`), or capitals and then digits (`S4`, `S1_25`, `O35`, `B0_5`). A `const` is in capitals and
/// underscores (`ROW_H`): a variable, as a lowercase name is.
fn css_token_name(s : String, called : Bool) -> Bool {
  let cs = s.to_array()
  if cs.length() == 0 || cs[0] < 'A' || cs[0] > 'Z' {
    return false
  }
  if called || cs.iter().any(fn(c) { c >= 'a' && c <= 'z' }) {
    return true
  }
  let mut i = 0
  while i < cs.length() && cs[i] >= 'A' && cs[i] <= 'Z' {
    i += 1
  }
  i < cs.length() &&
  cs[i] >= '0' &&
  cs[i] <= '9' &&
  cs[i:].iter().all(fn(c) { (c >= '0' && c <= '9') || c == '_' })
}

///|
/// A property's value as a style's text says it (`Fixed(14.0)`, `A(Fg,O35)`, `true`), or None when it is not all
/// literal: a variable, a field, a call of a function, an operator, another package's name. `@ui.` and `Type::`
/// before a token are left out (the text reads a token as its property's type has it).
fn css_value(f : MbtFile, idx : Array[Int]) -> String? {
  let toks = f.toks
  let out = StringBuilder()
  let mut n = 0
  while n < idx.length() {
    let i = idx[n]
    let t = toks[i]
    let next = if n + 1 < idx.length() { Some(toks[idx[n + 1]]) } else { None }
    match t.kind {
      "at" =>
        if t.text == "@ui" && next is Some(d) && d.text == "." {
          n += 2
          continue
        } else {
          return None
        }
      "ident" =>
        if t.text == "true" || t.text == "false" {
          out.write_string(t.text)
        } else if next is Some(d) && d.text == "::" && css_token_name(t.text, true) {
          n += 2
          continue
        } else if css_token_name(t.text, next is Some(d) && d.text == "(") {
          out.write_string(t.text)
        } else {
          return None
        }
      "num" => {
        // as its text reads it: an Int64's L, a UInt's U left out
        let mut s = t.text
        while s.has_suffix("L") || s.has_suffix("U") {
          s = s.exact_view(end=s.length() - 1).to_owned()
        }
        out.write_string(s)
      }
      "op" =>
        if t.text == "(" || t.text == ")" || t.text == "," || t.text == "-" {
          out.write_string(t.text)
        } else {
          return None
        }
      _ => return None
    }
    n += 1
  }
  if idx.length() == 0 {
    None
  } else {
    Some(out.to_string())
  }
}

///|
/// A `style(…)`'s arguments (a state's `patch(…)`'s, with states false) as a style's text, or None when one is not
/// all literal: `row h=S7 px=S2 hovered{bg=Hover}`
fn css_of_args(
  f : MbtFile,
  args : Array[(String?, Array[Int])],
  states : Bool,
) -> String? {
  let toks = f.toks
  let items = []
  for a in args {
    let (label, idx) = a
    guard label is Some(lb) else { return None }
    if states && css_states.contains(lb) {
      // patch(…) or @ui.patch(…), all of the value
      let at = if idx.length() >= 3 && toks[idx[0]].kind == "at" { 2 } else { 0 }
      if !(
          at < idx.length() &&
          (at == 0 || (toks[idx[0]].text == "@ui" && toks[idx[1]].text == ".")) &&
          toks[idx[at]].text == "patch" &&
          at + 1 < idx.length() &&
          toks[idx[at + 1]].text == "(" &&
          toks[idx[at + 1]].end == idx[idx.length() - 1]
        ) {
        return None
      }
      guard css_of_args(f, f.args_of(idx[at + 1]), false) is Some(inner) else {
        return None
      }
      items.push("\{lb}{\{inner}}")
    } else if css_props.contains(lb) {
      guard css_value(f, idx) is Some(v) else { return None }
      if lb == "row" || lb == "clip" {
        match v {
          "true" => items.push(lb)
          "false" => items.push(lb + "=false")
          _ => return None
        }
      } else {
        items.push("\{lb}=\{v}")
      }
    } else {
      return None
    }
  }
  Some(items.join(" "))
}

///|
/// style-text: a `style(…)` in a top-level `let` (a named style, a `.then(…)` of one) whose properties are all
/// tokens and numbers is to be its text, `@ui.css("…")` (mbui's ui/style.mbt): moonc makes each such call ~5-10 KB of C in
/// `moonbit_init`, run as the app starts, built again on every build (2026-10-24). One naming a variable, worked
/// out, or in a function stays `style(…)`. Bare `style(` is counted where the `let` says `Style` (mbui's own
/// package).
fn lint_style_text(f : MbtFile, out : Array[Finding]) -> Unit {
  if f.test_file {
    return
  }
  let toks = f.toks
  for c in f.calls {
    if c.is_def || c.name != "style" || c.item < 0 || f.in_test(c.at) {
      continue
    }
    let it = f.items[c.item]
    if it.kind != "let" {
      continue
    }
    let ok = if c.kind == "pkg" {
      c.qual == "@ui"
    } else if c.kind == "bare" {
      let mut said = false
      let mut k = it.start
      while k < c.at && toks[k].text != "=" {
        if toks[k].kind == "ident" && toks[k].text == "Style" {
          said = true
        }
        k += 1
      }
      said
    } else {
      false
    }
    if !ok {
      continue
    }
    match css_of_args(f, c.args, true) {
      Some(text) => {
        let pre = if c.kind == "pkg" { "@ui." } else { "" }
        out.push(
          finding(
            "style-text",
            f.rel,
            toks[c.at].line,
            "\{f.line_text(c.at)}   write: \{pre}css(\"\{text}\")",
          ),
        )
      }
      None => ()
    }
  }
}

///|
/// Whether the call `c` reads the frames' clock where it is followed (build-clock).
fn build_clock_read(f : MbtFile, c : Call, returns : Map[String, String]) -> Bool {
  if c.kind == "method" {
    if build_clock_methods.contains(c.name) {
      return true
    }
    if c.name == "now" || c.name == "cycle" {
      return match f.recv_type(c.at, returns) {
        Some(t) => t == "Ctx"
        None => c.at >= 2 && (f.toks[c.at - 2].text == "c" || f.toks[c.at - 2].text == "ctx")
      }
    }
    false
  } else {
    c.kind == "bare" && (c.name == "clock_read" || c.name == "clock_read_here")
  }
}

///|
/// A motion's reads of the frames' clock, followed (build-clock)
let build_clock_methods : Array[String] = ["now_before", "now_of", "shows_motion"]

///|
/// What a frame's paint is given to read as it paints, a closure each (Ctx::look_by and the rest): what is read in it
/// is read as the frame is painted, not built (build-clock)
let paint_takers : Array[String] = [
  "look_by", "moved_by", "bg_by", "ink_by", "notch_by", "cut_across_by", "glyphs_by", "cycle_look",
]

///|
/// Where a frame's paint begins (mbui's ui: frame_paint, and Ctx::paint, which it and what keeps a row's drawing
/// call): what only they call, and only what that calls, is read as the frame is painted (build-clock)
let paint_roots : Array[String] = ["frame_paint", "paint"]

///|
/// The package paint's roots are in (paint_roots)
let paint_root_pkg : String = "src/ui"

///|
/// The tokens of `f` given to a paint taker as what it reads as it paints (paint_takers' arguments)
fn paint_args(f : MbtFile) -> Map[Int, Unit] {
  let out : Map[Int, Unit] = Map([])
  for c in f.calls {
    if c.kind == "method" && !c.is_def && paint_takers.contains(c.name) {
      for a in c.args {
        for i in a.1 {
          out[i] = ()
        }
      }
    }
  }
  out
}

///|
/// Whether token `k` of `f` is read as a frame is painted: in what a paint taker is given, or in a function only
/// paint calls (paint_fns)
fn in_paint(f : MbtFile, k : Int, paint_at : Map[Int, Unit], painted : Map[String, Unit]) -> Bool {
  if paint_at.contains(k) {
    return true
  }
  let it = f.item_of[k]
  it >= 0 &&
  f.items[it].kind == "fn" &&
  painted.contains(pkg_of(f.rel) + "|" + last_name(f.items[it].name))
}

///|
/// The functions of each package called only as a frame is painted (by its name, package by package: `pkg|name`):
/// paint's roots, and those every call of which (outside the tests) is in what a paint taker is given or in a function
/// so called
fn paint_fns(files : Array[MbtFile]) -> Map[String, Unit] {
  // each function's calls in its package: where (the file, the token)
  let sites : Map[String, Array[(MbtFile, Int)]] = Map([])
  let defined : Map[String, Unit] = Map([])
  let args : Map[String, Map[Int, Unit]] = Map([])
  for f in files {
    if f.test_file {
      continue
    }
    let pkg = pkg_of(f.rel)
    args[f.rel] = paint_args(f)
    for it in f.items {
      if it.kind == "fn" && it.name != "" {
        defined[pkg + "|" + last_name(it.name)] = ()
      }
    }
    for c in f.calls {
      if c.is_def || f.in_test(c.at) {
        continue
      }
      let key = pkg + "|" + c.name
      match sites.get(key) {
        Some(a) => a.push((f, c.at))
        None => sites[key] = [(f, c.at)]
      }
    }
  }
  let painted : Map[String, Unit] = Map([])
  for name in paint_roots {
    if defined.contains(paint_root_pkg + "|" + name) {
      painted[paint_root_pkg + "|" + name] = ()
    }
  }
  let mut changed = true
  while changed {
    changed = false
    for key, _ in defined {
      if painted.contains(key) {
        continue
      }
      match sites.get(key) {
        Some(a) if a.length() > 0 &&
          a.iter().all(fn(s) {
            let (f, k) = s
            in_paint(f, k, args.get(f.rel).unwrap_or(Map([])), painted)
          }) => {
          painted[key] = ()
          changed = true
        }
        _ => ()
      }
    }
  }
  painted
}

///|
/// The types whose value moves by the clock, read as they are (build-motion)
let motion_types : Array[String] = ["Anim", "Way"]

///|
/// What @motion's functions give that moves by the clock, by their name, where no file linted says (build-motion: the
/// app's run, @motion not among its files)
let motion_returns : Array[(String, String)] = [("anim", "Anim"), ("told", "Anim")]

///|
/// The readers themselves, and what they read in to give it (build-motion): not counted inside them
let motion_readers : Array[String] = ["Anim::get", "Way::get", "animate", "pressing"]

///|
/// The fields of the files' structs of a type that moves by the clock (`fade : @motion.Anim`), by their name
/// (build-motion: `s.fade.get()`)
fn motion_fields(files : Array[MbtFile]) -> Map[String, Unit] {
  let out : Map[String, Unit] = Map([])
  for f in files {
    for it in f.items {
      if it.kind != "struct" {
        continue
      }
      for j in it.start..<(it.end - 1) {
        let t = f.toks[j]
        if t.kind == "ident" && f.toks[j + 1].text == ":" {
          match f.type_at(j + 2) {
            Some(ty) if motion_types.contains(ty) => out[t.text] = ()
            _ => ()
          }
        }
      }
    }
  }
  out
}

///|
/// Whether the call `c` reads an animated value as it is built (build-motion): @motion.animate (its value this
/// frame; motion's own `animate` in motion), or `get` on an Anim or a Way (told by its type where the receiver is
/// said, by its field where it is one: motion_fields)
fn motion_read_built(
  f : MbtFile,
  c : Call,
  returns : Map[String, String],
  fields : Map[String, Unit],
) -> Bool {
  if c.is_def {
    return false
  }
  if c.item >= 0 && motion_readers.contains(f.items[c.item].name) && under(f.rel, ["src/motion"]) {
    return false
  }
  if c.name == "animate" &&
    ((c.kind == "pkg" && c.qual == "@motion") || (c.kind == "bare" && under(f.rel, ["src/motion"]))) {
    return true
  }
  if c.kind != "method" || c.name != "get" {
    return false
  }
  let r = c.at - 2
  if r < 0 {
    return false
  }
  let rt = f.toks[r]
  // (a field: `s.fade.get()`)
  if rt.kind == "ident" && r > 0 && f.toks[r - 1].text == "." {
    return fields.contains(rt.text)
  }
  // (made by @motion's own, said so: `let a = @motion.told(…)`, whatever the files linted name `told`)
  if rt.kind == "ident" && motion_made(f, r) {
    return true
  }
  f.recv_type(c.at, returns) is Some(t) && motion_types.contains(t)
}

///|
/// Whether the name at `r` is let to what one of @motion's functions that give a moving value makes (`let a =
/// @motion.told(…)`), the nearest such let before it in its item (build-motion)
fn motion_made(f : MbtFile, r : Int) -> Bool {
  let toks = f.toks
  let name = toks[r].text
  let it = f.item_of[r]
  let lo = if it >= 0 { f.items[it].start } else { 0 }
  let mut j = r - 1
  while j >= lo {
    if toks[j].kind == "ident" &&
      toks[j].text == name &&
      j > 0 &&
      (toks[j - 1].text == "let" || toks[j - 1].text == "mut") &&
      j + 1 < toks.length() &&
      toks[j + 1].text == "=" {
      return j + 4 < toks.length() &&
        toks[j + 2].kind == "at" &&
        toks[j + 2].text == "@motion" &&
        toks[j + 3].text == "." &&
        motion_returns.iter().any(fn(m) { m.0 == toks[j + 4].text })
    }
    j -= 1
  }
  false
}

///|
/// The arguments, by their label, that hand what they are given to a paint taker (a list row's `ground_by`, a row's
/// band's `lit_by`: Ctx::bg_by): what is read in them is read as the frame is painted (build-clock, build-motion)
let paint_labels : Array[String] = ["ground_by", "lit_by"]

///|
/// What is given to a paint taker (`paint_at`), with what flows there: an argument of a paint label's
/// (paint_labels), and each closure let to a name that goes only there, or only into another such let (`let ground =
/// fn() { … }` handed on as `ground_by=ground`; `let (band, band_by) = …` with `lit_by=band_by`): the closures in
/// its value read as the frame is painted (build-clock, build-motion)
fn paint_flows(f : MbtFile, paint_at : Map[Int, Unit]) -> Map[Int, Unit] {
  let toks = f.toks
  let n = toks.length()
  let out : Map[Int, Unit] = Map([])
  for k, _ in paint_at {
    out[k] = ()
  }
  for c in f.calls {
    if c.is_def {
      continue
    }
    for a in c.args {
      let labelled = match a.0 {
        Some(l) => paint_labels.contains(l)
        None =>
          a.1.length() >= 3 &&
          toks[a.1[0]].kind == "ident" &&
          paint_labels.contains(toks[a.1[0]].text) &&
          toks[a.1[1]].text == "?" &&
          toks[a.1[2]].text == "="
      }
      if labelled {
        for i in a.1 {
          out[i] = ()
        }
      }
    }
  }
  // each let: the names it binds, its value's tokens (to the end of its line, past what it opens), whether a closure is
  // in it
  let lets : Array[(Array[Int], Int, Int)] = []
  for k, t in toks {
    if t.kind != "ident" || t.text != "let" || f.in_test(k) {
      continue
    }
    let mut j = k + 1
    if j < n && toks[j].text == "mut" {
      j += 1
    }
    if j >= n {
      continue
    }
    let names : Array[Int] = []
    if toks[j].kind == "ident" {
      names.push(j)
      j += 1
    } else if toks[j].text == "(" && toks[j].end >= 0 {
      for x in (j + 1)..<toks[j].end {
        if toks[x].kind == "ident" {
          names.push(x)
        }
      }
      j = toks[j].end + 1
    } else {
      continue
    }
    // (its type, where said)
    if j < n && toks[j].text == ":" {
      while j < n && toks[j].text != "=" && toks[j].line == toks[k].line {
        j = if is_open(toks[j]) && toks[j].end >= 0 { toks[j].end + 1 } else { j + 1 }
      }
    }
    if j >= n || toks[j].text != "=" {
      continue
    }
    let start = j + 1
    let mut e = start
    while e < n {
      let next = if is_open(toks[e]) && toks[e].end >= 0 { toks[e].end + 1 } else { e + 1 }
      if next >= n {
        e = n
        break
      }
      if toks[next].line > toks[next - 1].line && !value_goes_on(toks[next]) {
        e = next
        break
      }
      e = next
    }
    lets.push((names, start, e))
  }
  // the names let to a closure, or to what holds one of them (deferred): those whose every use is where it is painted,
  // or in another such let's value, are painted. (Names by item and text: `item|name`.)
  let key = fn(x : Int) { "\{f.item_of[x]}|\{toks[x].text}" }
  let uses : Map[String, Array[Int]] = Map([])
  for x, t in toks {
    // (a name's uses: not a field, nor an argument's label, `name=` or `name?=`, which is no use of a let of that name)
    let label = x + 1 < n &&
      (toks[x + 1].text == "=" || (toks[x + 1].text == "?" && x + 2 < n && toks[x + 2].text == "="))
    if t.kind == "ident" && !(x > 0 && toks[x - 1].text == ".") && !label {
      let k = key(x)
      match uses.get(k) {
        Some(a) => a.push(x)
        None => uses[k] = [x]
      }
    }
  }
  let deferred : Array[Bool] = Array::make(lets.length(), false)
  let deferred_names : Map[String, Unit] = Map([])
  let mut changed = true
  while changed {
    changed = false
    for i, l in lets {
      if deferred[i] {
        continue
      }
      let (names, s0, e0) = l
      let mut has = false
      for x in s0..<e0 {
        let t = toks[x]
        if t.kind == "ident" &&
          ((t.text == "fn" && x + 1 < n && toks[x + 1].text == "(") ||
          (!(x > 0 && toks[x - 1].text == ".") && deferred_names.contains(key(x)))) {
          has = true
          break
        }
      }
      if has {
        deferred[i] = true
        for m in names {
          deferred_names[key(m)] = ()
        }
        changed = true
      }
    }
  }
  let painted : Array[Bool] = deferred.copy()
  let mut shrunk = true
  while shrunk {
    shrunk = false
    // (where a painted let's value is)
    let in_value : Array[Bool] = Array::make(n, false)
    for i, l in lets {
      if painted[i] {
        for x in l.1..<l.2 {
          in_value[x] = true
        }
      }
    }
    for i, l in lets {
      if !painted[i] {
        continue
      }
      let (names, _, _) = l
      // (painted where any name it binds goes only where it is painted, none of them called as it is built)
      let mut any = false
      let mut called = false
      for m in names {
        let mut only = true
        // (one use at least: a closure let and never handed on is no paint's)
        let mut used = false
        for x in uses.get(key(m)).unwrap_or([]) {
          if x <= m {
            continue
          }
          used = true
          if out.contains(x) || in_value[x] {
            continue
          }
          only = false
          if x + 1 < n && toks[x + 1].text == "(" {
            called = true
          }
        }
        if only && used {
          any = true
        }
      }
      if !any || called {
        painted[i] = false
        shrunk = true
      }
    }
  }
  // (the closures in a painted let's value: what is read in them is read as it is painted)
  for i, l in lets {
    if !painted[i] {
      continue
    }
    let (_, s0, e0) = l
    for x in s0..<e0 {
      if toks[x].kind == "ident" && toks[x].text == "fn" && x + 1 < n && toks[x + 1].text == "(" && toks[x + 1].end >= 0 {
        let mut b = toks[x + 1].end + 1
        while b < e0 && !(toks[b].text == "{" && toks[b].end >= 0) {
          b += 1
        }
        if b < e0 {
          for y in x..=toks[b].end {
            out[y] = ()
          }
        }
      }
    }
  }
  out
}

///|
/// Whether a line starting with `t` goes on the expression of the line before it (a method chained, a pipe, an
/// operator, an else)
fn value_goes_on(t : Tok) -> Bool {
  [".", "|>", "&&", "||", "+", "-", "*", "/", "else"].contains(t.text)
}

///|
/// Whether what is at `k` is the last argument of a source's call: its parenthesis opened right after `(….call)` or
/// `(….call_bytes)` (empty-on-done).
fn done_of_call(toks : Array[Tok], k : Int) -> Bool {
  let mut depth = 0
  let mut i = k - 1
  while i >= 0 {
    let t = toks[i].text
    if t == ")" || t == "]" || t == "}" {
      depth = depth + 1
    } else if t == "(" || t == "[" || t == "{" {
      if depth == 0 {
        return t == "(" &&
          i >= 3 &&
          toks[i - 1].text == ")" &&
          (toks[i - 2].text == "call" || toks[i - 2].text == "call_bytes") &&
          toks[i - 3].text == "."
      }
      depth = depth - 1
    }
    i = i - 1
  }
  false
}

///|
/// A call as `run_first`'s names say one: `@pkg.name` a package's, a bare name its own.
fn call_named(c : Call, names : Array[String]) -> Bool {
  if c.kind == "bare" {
    names.contains(c.name)
  } else if c.kind == "pkg" {
    names.contains(c.qual + "." + c.name)
  } else {
    false
  }
}

///|
/// The spans of the functions written in item `i` of `f` (fn(…) { … } inside it, not its own): what they read is read
/// when they are called, not where they are written.
fn lambda_spans(f : MbtFile, i : Int) -> Array[(Int, Int)] {
  let it = f.items[i]
  let toks = f.toks
  let mut open = it.start
  while open <= it.end && open < toks.length() && toks[open].text != "{" {
    open += 1
  }
  let out = []
  for k in (open + 1)..<@cmp.minimum(it.end + 1, toks.length()) {
    if toks[k].kind == "ident" && toks[k].text == "fn" && k + 1 < toks.length() && toks[k + 1].text == "(" {
      let p = toks[k + 1].end
      if p < 0 {
        continue
      }
      let mut b = p + 1
      while b < toks.length() && toks[b].text != "{" {
        b += 1
      }
      if b < toks.length() && toks[b].end >= 0 {
        out.push((k, toks[b].end))
      }
    }
  }
  out
}

///|
/// read-before-run: in a test file, a test that reads the app's words or language (`run_first.reads`) before it starts
/// its own run of the app (`run_first.starts`, Tester::new, or a function that does one of them before anything it
/// reads: by its name, in any file), itself or by a function of its own file it calls first: what it reads is what the
/// test before it in the process left
fn lint_read_before_run(files : Array[MbtFile], cfg : Config, out : Array[Finding]) -> Unit {
  if cfg.run_reads.is_empty() {
    return
  }
  // each function by its name: where it is (its file, its item)
  let fns : Map[String, Array[(Int, Int)]] = Map([])
  // what gives a Tester back (its type after `->` names Tester)
  let makers : Map[String, Unit] = Map([])
  for fi, f in files {
    for i, it in f.items {
      if it.kind != "fn" || it.name == "" {
        continue
      }
      let parts = it.name.split("::").to_array()
      let short = parts[parts.length() - 1].to_owned()
      match fns.get(short) {
        Some(a) => a.push((fi, i))
        None => fns[short] = [(fi, i)]
      }
      let mut k = it.start
      let mut arrow = false
      while k <= it.end && k < f.toks.length() {
        let t = f.toks[k]
        if t.text == "(" && t.end >= 0 && !arrow {
          k = t.end + 1
          continue
        }
        if t.text == "{" {
          break
        }
        if t.text == "->" {
          arrow = true
        } else if arrow && t.kind == "ident" && t.text == "Tester" {
          makers[short] = ()
          break
        }
        k += 1
      }
    }
  }
  // what an item does first: 1 starts a run, 2 reads, 0 neither; and the call that does it
  let memo : Map[String, (Int, Int)] = Map([])
  fn first(fi : Int, i : Int, local_reads : Bool) -> (Int, Int) {
    let key = "\{fi}:\{i}:\{local_reads}"
    match memo.get(key) {
      Some(r) => return r
      None => ()
    }
    memo[key] = (0, -1) // (a cycle: neither)
    let f = files[fi]
    let spans = lambda_spans(f, i)
    let mut got = (0, -1)
    for c in f.calls {
      if c.item != i || c.is_def || spans.iter().any(fn(sp) { c.at > sp.0 && c.at <= sp.1 }) {
        continue
      }
      let kind = if call_named(c, cfg.run_starts) ||
        (c.kind == "type" && c.qual == "Tester" && c.name == "new") ||
        ((c.kind == "bare" || c.kind == "pkg") && makers.contains(c.name)) {
        1
      } else if call_named(c, cfg.run_reads) {
        2
      } else if c.kind == "bare" || c.kind == "pkg" {
        // a function: starting a run first, wherever it is; reading first, one of this file's
        let mut k = 0
        for at in fns.get(c.name).unwrap_or([]) {
          if at.0 == fi && at.1 == i {
            continue
          }
          let (fk, _) = first(at.0, at.1, local_reads && at.0 == fi)
          if fk == 1 || (fk == 2 && local_reads && at.0 == fi && c.kind == "bare") {
            k = fk
            break
          }
        }
        k
      } else {
        0
      }
      if kind != 0 && (got.1 < 0 || c.at < got.1) {
        got = (kind, c.at)
      }
    }
    memo[key] = got
    got
  }
  for fi, f in files {
    if !f.test_file {
      continue
    }
    for i, it in f.items {
      if it.kind != "test" {
        continue
      }
      let (k, at) = first(fi, i, true)
      if k == 2 {
        out.push(finding("read-before-run", f.rel, f.toks[at].line, f.line_text(at)))
      }
    }
  }
}

///|
/// reset-by-hand: in a test file, a test or a function that puts the app back by hand (`reset_by_hand.names`) makes a
/// Tester after the last of them (Tester::new, or a function said to give one back: its type after `->` names Tester),
/// else what it put back is left marked for a Tester to come, which is the next test's
fn lint_reset_by_hand(files : Array[MbtFile], cfg : Config, out : Array[Finding]) -> Unit {
  if cfg.reset_by_hand.is_empty() {
    return
  }
  // what gives a Tester back, by name, in every file
  let makers : Map[String, Unit] = Map([])
  for f in files {
    for it in f.items {
      if it.kind != "fn" || it.name == "" {
        continue
      }
      let mut arrow = false
      let mut k = it.start
      while k <= it.end && k < f.toks.length() {
        let t = f.toks[k]
        if t.text == "{" && arrow {
          break
        }
        if t.text == "->" {
          arrow = true
        } else if arrow && t.kind == "ident" && t.text == "Tester" {
          let parts = it.name.split("::").to_array()
          makers[parts[parts.length() - 1].to_owned()] = ()
          break
        }
        k += 1
      }
    }
  }
  for f in files {
    if !f.test_file {
      continue
    }
    let last : Map[Int, Int] = Map([]) // item -> the last call putting the app back in it
    for c in f.calls {
      if !c.is_def && c.kind == "bare" && c.item >= 0 && cfg.reset_by_hand.contains(c.name) {
        last[c.item] = c.at
      }
    }
    for item, at in last {
      let made = f.calls.iter().any(fn(c) {
        c.item == item &&
        c.at > at &&
        !c.is_def &&
        (
          (c.kind == "type" && c.qual.has_suffix("Tester") && c.name == "new") ||
          ((c.kind == "bare" || c.kind == "pkg") && makers.contains(c.name))
        )
      })
      if !made {
        out.push(finding("reset-by-hand", f.rel, f.toks[at].line, f.line_text(at)))
      }
    }
  }
}

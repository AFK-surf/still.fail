// build-effect: what a view tells outside while it builds (rule_words): the effects (a field call (x.call)(…), a
// package's effect, a native view's own: its reload, its seek) and the app's functions that do one (found to a fixed
// point), called in a function given the Ctx, other than in Ctx::after_build, a callback (fn(…) { … }) or under an
// input the frame takes.

///|
priv struct Eff {
  cfg : Config
  // the app's functions by (package, name): where they are defined (their file and definition's call)
  defs : Map[String, (MbtFile, Call)]
  calls_at : Map[String, Call]
  handlers : Map[String, Bool]
  asking : Map[String, Unit]
  shapes : Map[String, (Map[String, Unit], Map[String, Unit])]
}

///|
fn at_key(rel : String, k : Int) -> String {
  rel + "\u{1f}" + k.to_string()
}

///|
fn header_end(f : MbtFile, it : Item) -> Int {
  let toks = f.toks
  let mut k = it.start
  while k <= it.end && !(toks[k].kind == "op" && toks[k].text == "{") {
    if toks[k].kind == "op" &&
      (toks[k].text == "(" || toks[k].text == "[") &&
      toks[k].end >= 0 {
      k = toks[k].end
    }
    k += 1
  }
  k
}

///|
fn is_view(f : MbtFile, it : Item) -> Bool {
  if it.kind != "fn" {
    return false
  }
  let b = header_end(f, it)
  for k in it.start..<@cmp.minimum(b, it.end) {
    if f.toks[k].kind == "ident" && f.toks[k].text == "Ctx" {
      return true
    }
  }
  false
}

///|
/// The positional ones of a call's arguments or a definition's parameters (not `x=`, `x~`, `x? :`)
fn positional(f : MbtFile, args : Array[(String?, Array[Int])]) -> Array[Array[Int]] {
  args
  .filter(fn(a) {
    a.0 is None &&
    a.1.length() > 0 &&
    !(a.1.length() > 1 && f.toks[a.1[1]].text == "?")
  })
  .map(fn(a) { a.1 })
}

///|
/// Whether function key calls its i-th positional parameter only as an input is taken (a button's answer:
/// dv_empty(c, …, fn() { … }) whose `on_tap()` is under its `clicked`)
fn Eff::handler_param(self : Eff, key : String, i : Int) -> Bool {
  let hk = key + "\u{1e}" + i.to_string()
  match self.handlers.get(hk) {
    Some(v) => return v
    None => ()
  }
  if !self.defs.contains(key) || self.asking.contains(hk) {
    return false
  }
  let (df, dc) = self.defs[key]
  let params = positional(df, dc.args)
  if i >= params.length() || df.toks[params[i][0]].kind != "ident" {
    return false
  }
  let name = df.toks[params[i][0]].text
  self.asking[hk] = ()
  let sites = df.calls
    .filter(fn(c) {
      c.item == dc.item && c.kind == "bare" && !c.is_def && c.name == name
    })
    .map(fn(c) { c.at })
  // given on whole, not called, to what runs it later (build_effect.later: settings' confirm(…, run) handing `run` to
  // @sf.confirm): a handler too
  let body = df.items[dc.item]
  let passed = []
  let mut bare_other = false
  for k in header_end(df, body)..<body.end {
    let t = df.toks[k]
    if t.kind != "ident" || t.text != name || (k > 0 && df.toks[k - 1].text == ".") {
      continue
    }
    if k + 1 < df.toks.length() && df.toks[k + 1].kind == "op" && df.toks[k + 1].text == "(" {
      continue
    }
    if self.given_later(df, dc.item, k) {
      passed.push(k)
    } else {
      bare_other = true
    }
  }
  let got = (sites.length() > 0 || passed.length() > 0) &&
    !(passed.length() > 0 && bare_other) &&
    sites.iter().all(fn(k) { self.exempt(df, k) })
  self.asking.remove(hk)
  self.handlers[hk] = got
  got
}

///|
/// Whether the token at k (in item `item`) is a whole argument of a call that runs what it is given later
/// (build_effect.later).
fn Eff::given_later(self : Eff, f : MbtFile, item : Int, k : Int) -> Bool {
  f.calls.iter().any(fn(c) {
    c.item == item &&
    c.kind == "pkg" &&
    self.cfg.effect_later.contains("\{c.qual}.\{c.name}") &&
    c.args.iter().any(fn(a) { a.1.length() == 1 && a.1[0] == k })
  })
}

///|
/// Whether the closure whose body opens at o runs later than the build (a callback: what an effect is answered
/// with, an event's handler, a fiber's body), not as it builds (a box's children: c.box(fn() { … }))
fn Eff::later(self : Eff, f : MbtFile, o : Int) -> Bool {
  let toks = f.toks
  // the call it is an argument of, and its label
  let mut lab : String? = None
  let mut b = o - 1
  while b >= 0 && !(toks[b].kind == "op" && (toks[b].text == "(" || toks[b].text == ",")) {
    if is_close(toks[b]) {
      let ob = f.open_of(b)
      b = (if ob >= 0 { ob } else { b }) - 1
      continue
    }
    if toks[b].kind == "op" &&
      (toks[b].text == "=" || toks[b].text == "~") &&
      b > 0 &&
      toks[b - 1].kind == "ident" {
      lab = Some(toks[b - 1].text)
    }
    b -= 1
  }
  match lab {
    Some(l) => if l.has_prefix("on_") || later_labels.contains(l) { return true }
    None => ()
  }
  // not given to a call (a field's value, a let's): what it is called by is not the build
  if b < 0 || (toks[b].text != "(" && toks[b].text != ",") {
    return true
  }
  // back to the call's opening bracket
  let mut p = b
  while p >= 0 {
    let t = toks[p]
    if t.kind == "op" && t.text == "(" && t.end >= 0 && t.end > o {
      break
    }
    if t.kind == "op" && (t.text == "[" || t.text == "{") && t.end >= 0 && t.end > o {
      return true // in an array or a struct: a value, not run as it builds
    }
    p -= 1
  }
  if p < 1 {
    return false
  }
  let callee = toks[p - 1]
  // (src.call)(…, fn(res) { … }): an effect's answer
  if callee.kind == "op" &&
    callee.text == ")" &&
    p >= 4 &&
    toks[p - 2].kind == "ident" &&
    self.cfg.effect_fields.contains(toks[p - 2].text) {
    return true
  }
  if callee.kind == "ident" && later_calls.contains(callee.text) {
    return true
  }
  // given to what runs it later (build_effect.later: an app's presenters)
  match self.calls_at.get(at_key(f.rel, p - 1)) {
    Some(call) if call.kind == "pkg" && self.cfg.effect_later.contains("\{call.qual}.\{call.name}") => return true
    _ => ()
  }
  // given to an app's function that calls it only under an input (a button's own callback)
  match self.calls_at.get(at_key(f.rel, p - 1)) {
    Some(call) =>
      if call.kind == "bare" {
        for i, a in positional(f, call.args) {
          if a[0] <= o && o <= a[a.length() - 1] {
            return self.handler_param(reader_key(pkg_of(f.rel), call.name), i)
          }
        }
      }
    None => ()
  }
  false
}

///|
/// Whether the closure at o (its `fn`) is given to one of the Ctx's own (c.list(…, fn(i) { … }): its rows, built as
/// the frame builds)
fn built_by_ctx(f : MbtFile, o : Int) -> Bool {
  let toks = f.toks
  let mut p = o - 1
  while p >= 0 {
    let t = toks[p]
    if t.kind == "op" && t.text == "(" && t.end >= 0 && t.end > o {
      break
    }
    p -= 1
  }
  p >= 3 &&
  toks[p - 1].kind == "ident" &&
  toks[p - 2].text == "." &&
  toks[p - 3].kind == "ident" &&
  toks[p - 3].text == "c"
}

///|
/// In function it: the lets that hold what a widget took (`let k = segmented(c, …)`, `let typed =
/// c.code_field(…)`, and the lets worked out from them), and the fields a press sets (`p.scrub = …` under a
/// `pressed`): a condition comparing the one (`!=`, `is`) or testing the other once let go is an input's
fn Eff::item_shapes(
  self : Eff,
  f : MbtFile,
  it : Item,
) -> (Map[String, Unit], Map[String, Unit]) {
  let key = at_key(f.rel, it.start)
  match self.shapes.get(key) {
    Some(s) => return s
    None => ()
  }
  let toks = f.toks
  let values : Map[String, Unit] = Map::new()
  let pressed_fields : Map[String, Unit] = Map::new()
  for k in it.start..<(it.end - 2) {
    let t = toks[k]
    if t.kind == "ident" &&
      t.text == "let" &&
      toks[k + 1].kind == "ident" &&
      toks[k + 2].text == "=" {
      // the let's expression: to the end of its line, its brackets whole
      let e = []
      let mut j = k + 3
      while j <= it.end && toks[j].line == toks[k].line {
        if is_open(toks[j]) && toks[j].end >= 0 {
          for x in j..=toks[j].end {
            e.push(x)
          }
          j = toks[j].end + 1
          continue
        }
        e.push(j)
        j += 1
      }
      let mut took = false
      for n in 0..<@cmp.minimum(5, e.length()) {
        let i = e[n]
        let ti = toks[i]
        if ti.kind == "ident" && i + 1 < toks.length() && toks[i + 1].text == "(" {
          // a widget whose answer is what it took (segmented(c, …), c.code_field(…))
          took = input_value_calls.contains(ti.text)
          break
        }
      }
      if took ||
        e.iter().any(fn(i) { toks[i].kind == "ident" && values.contains(toks[i].text) }) {
        values[toks[k + 1].text] = ()
      }
    }
    if t.kind == "op" &&
      t.text == "." &&
      toks[k + 1].kind == "ident" &&
      toks[k + 2].kind == "op" &&
      toks[k + 2].text == "=" {
      if f
        .enclosing_conditions(k)
        .iter()
        .any(fn(cond) {
          cond.iter().any(fn(i) { toks[i].kind == "ident" && toks[i].text == "pressed" })
        }) {
        pressed_fields[toks[k + 1].text] = ()
      }
    }
  }
  self.shapes[key] = (values, pressed_fields)
  (values, pressed_fields)
}

///|
fn Eff::exempt(self : Eff, f : MbtFile, k : Int) -> Bool {
  let toks = f.toks
  for o = k - 1; o >= 0; o = o - 1 {
    let t = toks[o]
    if t.kind != "op" || (t.text != "(" && t.text != "{") || t.end < 0 || t.end < k {
      continue
    }
    if t.text == "(" &&
      o > 0 &&
      toks[o - 1].kind == "ident" &&
      (toks[o - 1].text == "after_build" || toks[o - 1].text == "tell") {
      return true
    }
    if t.text == "{" {
      // a callback's body: fn(…) { … } or fn(…) -> T { … }
      let mut j = o - 1
      if j >= 0 && toks[j].kind == "ident" && j > 0 && toks[j - 1].text == "->" {
        j -= 2
        while j >= 0 && toks[j].kind == "op" && (toks[j].text == ">" || toks[j].text == "]") {
          j -= 1
        }
      }
      if j >= 0 && toks[j].kind == "op" && toks[j].text == ")" {
        let ob = f.open_of(j)
        if ob > 0 && toks[ob - 1].kind == "ident" && toks[ob - 1].text == "fn" {
          // given what happened (fn(d) { … }: a stepper's change, an answer): a handler; fn() { … }: a box's
          // children, the build, unless what it is given to runs it later
          if (ob > 1 && toks[ob - 2].text == "async") || self.later(f, ob - 1) {
            return true
          }
          if j > ob + 1 && !built_by_ctx(f, ob - 1) {
            return true
          }
        }
      }
    }
  }
  let it = f.item_of[k]
  let (values, pressed_fields) = if it >= 0 {
    self.item_shapes(f, f.items[it])
  } else {
    (Map::new(), Map::new())
  }
  for cond in f.enclosing_conditions(k) {
    if cond.iter().any(fn(i) { toks[i].kind == "ident" && input_words.contains(toks[i].text) }) {
      return true
    }
    let names : Map[String, Unit] = Map::new()
    for i in cond {
      if toks[i].kind == "ident" {
        names[toks[i].text] = ()
      }
    }
    // what a widget took, compared: its choice other than what is kept, a code typed in
    if names.keys().any(fn(n) { values.contains(n) }) &&
      (names.contains("is") || cond.iter().any(fn(i) { toks[i].text == "!=" })) {
      return true
    }
    // what a press left, acted on once it is let go (a timeline's seek to where it was dragged)
    if !names.contains("pressed") &&
      cond
      .iter()
      .any(fn(i) {
        toks[i].text == "." &&
        i + 1 < toks.length() &&
        pressed_fields.contains(toks[i + 1].text)
      }) {
      return true
    }
    // a widget asked whether it was used (button(c, …), row(c, …): given the Ctx first), not a time or a layout
    // read (after(c, …), held(c, …))
    for i in cond {
      let t = toks[i]
      if t.kind == "ident" &&
        i + 2 < toks.length() &&
        toks[i + 1].text == "(" &&
        toks[i + 2].kind == "ident" &&
        toks[i + 2].text == "c" &&
        i + 3 < toks.length() &&
        (toks[i + 3].text == "," || toks[i + 3].text == ")") &&
        !not_input_calls.contains(t.text) {
        return true
      }
    }
  }
  false
}

///|
/// The effects in item it not exempt: (token index, what)
fn Eff::sites(
  self : Eff,
  f : MbtFile,
  it : Item,
  helpers : Map[String, Unit],
) -> Array[(Int, String)] {
  let toks = f.toks
  let got = []
  for k in it.start..=it.end {
    let t = toks[k]
    // (x.call)(…)
    if t.kind == "ident" &&
      self.cfg.effect_fields.contains(t.text) &&
      k >= 3 &&
      toks[k - 1].text == "." &&
      toks[k - 3].kind == "op" &&
      toks[k - 3].text == "(" &&
      k + 2 < toks.length() &&
      toks[k + 1].text == ")" &&
      toks[k + 2].text == "(" {
      if !self.exempt(f, k) {
        got.push((k, "(\{toks[k - 2].text}.\{t.text})"))
      }
    }
  }
  for c in f.calls {
    if c.is_def || c.at < it.start || c.at > it.end {
      continue
    }
    let name = if c.kind == "pkg" && self.cfg.effect_calls.contains("\{c.qual}.\{c.name}") {
      Some("\{c.qual}.\{c.name}")
    } else if c.kind == "bare" && helpers.contains(reader_key(pkg_of(f.rel), c.name)) {
      Some(c.name)
    } else if c.kind == "method" &&
      self.cfg.effect_methods.contains(c.name) &&
      c.at >= 2 &&
      !(toks[c.at - 2].kind == "ident" && toks[c.at - 2].text == "c") {
      Some("." + c.name)
    } else {
      None
    }
    match name {
      Some(n) => if !self.exempt(f, c.at) { got.push((c.at, n)) }
      None => ()
    }
  }
  got
}

///|
fn lint_build_effects(files : Array[MbtFile], cfg : Config, out : Array[Finding]) -> Unit {
  let app = files.filter(fn(f) { !f.test_file && !under(f.rel, cfg.framework) })
  let defs = Map::new()
  let calls_at = Map::new()
  for f in app {
    for c in f.calls {
      calls_at[at_key(f.rel, c.at)] = c
      if c.is_def && c.kind == "bare" {
        defs[reader_key(pkg_of(f.rel), c.name)] = (f, c)
      }
    }
  }
  let eff : Eff = {
    cfg,
    defs,
    calls_at,
    handlers: Map::new(),
    asking: Map::new(),
    shapes: Map::new(),
  }
  let fns : Array[(MbtFile, Item)] = []
  for f in app {
    for it in f.items {
      if it.kind == "fn" && it.name != "" {
        fns.push((f, it))
      }
    }
  }
  // what is done only on an input, an answer, after the build: a function every call of which is (an action: a
  // send, a pick's ask), its effects are the input's
  let callers : Map[String, Array[(MbtFile, Item, Int)]] = Map::new()
  for f in app {
    let pkg = pkg_of(f.rel)
    for c in f.calls {
      if c.kind == "bare" && !c.is_def && c.item >= 0 && f.items[c.item].kind == "fn" {
        let key = reader_key(pkg, c.name)
        let site = (f, f.items[c.item], c.at)
        match callers.get(key) {
          Some(a) => a.push(site)
          None => callers[key] = [site]
        }
      }
    }
  }
  let actions : Map[String, Unit] = Map::new()
  while true {
    let mut grew = false
    for x in fns {
      let (f, it) = x
      let key = reader_key(pkg_of(f.rel), it.name)
      if actions.contains(key) || !callers.contains(key) {
        continue
      }
      if callers[key]
        .iter()
        .all(fn(s) {
          let (cf, ci, k) = s
          eff.exempt(cf, k) || actions.contains(reader_key(pkg_of(cf.rel), ci.name))
        }) {
        actions[key] = ()
        grew = true
      }
    }
    if !grew {
      break
    }
  }
  let views : Map[String, Unit] = Map::new()
  for x in fns {
    let (f, it) = x
    if is_view(f, it) && !actions.contains(reader_key(pkg_of(f.rel), it.name)) {
      views[at_key(f.rel, it.start)] = ()
    }
  }
  let helpers : Map[String, Unit] = Map::new()
  while true {
    // (a bare call is to its package's own function: by its directory and name)
    let more = []
    for x in fns {
      let (f, it) = x
      let key = reader_key(pkg_of(f.rel), it.name)
      if !views.contains(at_key(f.rel, it.start)) &&
        !it.name.contains("::") &&
        !actions.contains(key) &&
        eff.sites(f, it, helpers).length() > 0 {
        more.push(key)
      }
    }
    if more.iter().all(fn(k) { helpers.contains(k) }) {
      break
    }
    for k in more {
      helpers[k] = ()
    }
  }
  for x in fns {
    let (f, it) = x
    if !views.contains(at_key(f.rel, it.start)) {
      continue
    }
    for s in eff.sites(f, it, helpers) {
      let (k, what) = s
      out.push(
        finding(
          "build-effect",
          f.rel,
          f.toks[k].line,
          "\{f.line_text(k)}   (\{what}, in \{it.name})",
        ),
      )
    }
  }
}

// The cascade: each element's declarations from the sheets whose rules select it (their @media holding in the room
// the widget has), its style attribute, sorted as CSS sorts them (!important first, then the author's over the
// defaults, then how specific, then which came later), custom properties worked out first and inherited, var() put in,
// shorthands set into their longhands where they come; then each property's computed value (style.mbt), inherited
// where it is inherited.

///|
/// Where the cascade is worked out: how wide the widget is (its @media's width, vw), whether it is drawn dark, whether
/// motion is reduced, the size of the root's words, the custom properties its root is given (the theme's tokens).
pub(all) struct Env {
  width : Double
  dark : Bool
  reduced_motion : Bool
  root_size : Double
  tokens : Array[(String, String)]
}

///|
/// A rule's declarations as they come to an element: their order key.
priv struct Hit {
  decl : Decl
  key : (Int, Int, Int)
}

///|
/// The sheets of a widget: the defaults (what draws it says them: an element with no CSS of its own drawn as the
/// rest of the app is), then the widget's own (its <style> elements, in order).
pub(all) struct Sheets {
  defaults : Sheet
  author : Sheet
}

///|
/// Whether a media query list holds.
pub fn media_holds(q : String, env : Env) -> Bool {
  let list = split_top(to_lower(q), ','.to_int())
  if list.is_empty() {
    return true
  }
  list.iter().any(fn(one) { media_one(one, env) })
}

///|
fn media_one(q : String, env : Env) -> Bool {
  let mut t = q.trim().to_string()
  let mut negate = false
  if t.has_prefix("not ") {
    negate = true
    t = t.view(start_offset=4).trim().to_string()
  }
  if t.has_prefix("only ") {
    t = t.view(start_offset=5).trim().to_string()
  }
  let mut ok = true
  for part in t.split(" and ") {
    let p = part.trim().to_string()
    let holds = if p == "all" || p == "screen" || p == "" {
      true
    } else if p == "print" || p == "speech" {
      false
    } else if p.has_prefix("(") && p.has_suffix(")") {
      media_feature(p.view(start_offset=1, end_offset=p.length() - 1).trim().to_string(), env)
    } else {
      false
    }
    if !holds {
      ok = false
    }
  }
  if negate {
    !ok
  } else {
    ok
  }
}

///|
fn media_feature(f : String, env : Env) -> Bool {
  let b : Basis = { em: env.root_size, rem: env.root_size, vw: env.width }
  let px = fn(v : String) { parse_len(v, b).map(fn(l) { l.resolve(env.width, auto=0.0) }) }
  match f.find(":") {
    Some(at) => {
      let name = f.view(end_offset=at).trim().to_string()
      let v = f.view(start_offset=at + 1).trim().to_string()
      match name {
        "prefers-color-scheme" => (v == "dark") == env.dark
        "prefers-reduced-motion" => (v == "reduce") == env.reduced_motion
        "min-width" => px(v).map(fn(x) { env.width >= x }).unwrap_or(false)
        "max-width" => px(v).map(fn(x) { env.width <= x }).unwrap_or(false)
        "width" => px(v).map(fn(x) { env.width == x }).unwrap_or(false)
        "hover" => v == "none"
        "any-hover" => v == "none"
        "pointer" | "any-pointer" => v == "coarse"
        "orientation" => v == "portrait"
        "prefers-contrast" => v == "no-preference"
        _ => false
      }
    }
    None =>
      // a range: (width >= 400px), (400px <= width)
      if f.contains(">=") || f.contains("<=") || f.contains(">") || f.contains("<") {
        let (op, at) = if f.contains(">=") {
          (">=", f.find(">=").unwrap())
        } else if f.contains("<=") {
          ("<=", f.find("<=").unwrap())
        } else if f.contains(">") {
          (">", f.find(">").unwrap())
        } else {
          ("<", f.find("<").unwrap())
        }
        let l = f.view(end_offset=at).trim().to_string()
        let r = f.view(start_offset=at + op.length()).trim().to_string()
        let (value, width_left) = if l == "width" { (px(r), true) } else { (px(l), false) }
        match value {
          Some(x) => {
            let w = env.width
            let (a, c) = if width_left { (w, x) } else { (x, w) }
            match op {
              ">=" => a >= c
              "<=" => a <= c
              ">" => a > c
              _ => a < c
            }
          }
          None => false
        }
      } else {
        f == "hover" && false
      }
  }
}

///|
/// The declarations selecting element `i` (its pseudo-element `element`: "" itself), in the order they apply.
fn hits_of(tree : Tree, sheets : Sheets, i : Int, element : String, env : Env, state : (Int, State) -> Bool) -> Array[Decl] {
  let hits : Array[Hit] = []
  let add = fn(sheet : Sheet, origin : Int) {
    for r in sheet.rules {
      if !r.media.iter().all(fn(m) { media_holds(m, env) }) {
        continue
      }
      let mut best = -1
      for s in r.selectors {
        if s.element == element && tree.matches(s, i, state) {
          let sp = s.specificity()
          if sp > best {
            best = sp
          }
        }
      }
      if best >= 0 {
        for d in r.decls {
          hits.push({ decl: d, key: ((if d.important { 1 } else { 0 }) * 10 + origin, best, r.order) })
        }
      }
    }
  }
  add(sheets.defaults, 0)
  add(sheets.author, 1)
  if element == "" {
    match tree.els[i].elem.attr("style") {
      Some(st) =>
        for k, d in parse_decls(st) {
          hits.push({ decl: d, key: ((if d.important { 1 } else { 0 }) * 10 + 2, 0, k) })
        }
      None => ()
    }
  }
  hits.sort_by(fn(a, b) {
    if a.key.0 != b.key.0 {
      a.key.0 - b.key.0
    } else if a.key.1 != b.key.1 {
      a.key.1 - b.key.1
    } else {
      a.key.2 - b.key.2
    }
  })
  hits.map(fn(h) { h.decl })
}

///|
/// What an element (or pseudo-element) comes to: its computed style and its custom properties.
pub(all) struct Cascaded {
  style : Style
  vars : Map[String, String]
  /// each longhand as declared, var() put in (what an SVG element's own properties are read from)
  specified : Map[String, String]
}

///|
/// The cascade of element `i`'s (pseudo-element `element`) declarations over its parent's (None: the root's,
/// given the tokens).
pub fn cascade(
  tree : Tree,
  sheets : Sheets,
  i : Int,
  element : String,
  parent : Cascaded?,
  env : Env,
  state : (Int, State) -> Bool,
) -> Cascaded {
  let decls = hits_of(tree, sheets, i, element, env, state)
  // custom properties: inherited, then set
  let vars : Map[String, String] = {}
  match parent {
    Some(p) => p.vars.each(fn(k, v) { vars[k] = v })
    None => for t in env.tokens { vars[t.0] = t.1 }
  }
  for d in decls {
    if d.name.has_prefix("--") {
      vars[d.name] = d.value
    }
  }
  // custom properties whose values use others: put in, those failing dropped (guaranteed-invalid)
  let lookup = fn(name : String) { vars.get(name) }
  let specified : Map[String, String] = {}
  let order : Array[String] = []
  let set = fn(name : String, value : String) {
    if !specified.contains(name) {
      order.push(name)
    }
    specified[name] = value
  }
  for d in decls {
    if d.name.has_prefix("--") {
      continue
    }
    match subst_vars(d.value, lookup) {
      Some(v) => expand(d.name, v, set)
      // invalid at computed-value time: unset
      None => set(d.name, "unset")
    }
  }
  let base = match parent {
    Some(p) => p.style
    None => Style::root(env)
  }
  let st = compute(specified, base, parent is None, env, vars)
  { style: st, vars, specified }
}

// What people, agents and stations wrote, at its longest: each field the core's schema marks `said` (said_paths.mbt,
// made by the core's scripts/shapes.ts) made long, with a line break and words that break late in it, as an agent's
// notice, a chat's title or a station's error may be. A fixture says what a screen shows; what the outside writes
// there has no length a fixture can promise: the squeeze sweep holds every screen to fit it at its longest
// (squeeze_said_wbtest.mbt).

///|
/// What is put after each piece of words someone outside the app wrote: longer than any window is wide, a line break in
/// it, and words that break late (a run's number, a file's name).
pub let said_more : String = " — 后面还有很长的一段话：agent 把 run 40208168565 和 squeeze_wbtest 的结果都写在这里，一直写下去也没有停\nand then a second line in English, written on and on for longer than any window is wide"

///|
/// Words someone outside the app wrote, at their longest; none stays none (what is not there is not made).
pub fn said_longest(s : String) -> String {
  if s == "" {
    s
  } else {
    s + said_more
  }
}

///|
/// `value` with the words at `path` (fields by name, `*` each item of a list or a map, `<tag>=<word>` a union's variant
/// where its tag says that word) at their longest, or made what `leaf` makes of them; the rest as it was.
pub fn said_stretch(value : Json, path : ArrayView[String], leaf? : (String) -> String = said_longest) -> Json {
  match path {
    [step, .. rest] if step.contains("=") =>
      // (a union's variant: on where its tag says that word)
      match (step.split("=").collect(), value) {
        ([tag, word], Object(m)) if m.get(tag.to_owned()) == Some(Json::string(word.to_owned())) =>
          said_stretch(value, rest, leaf~)
        _ => value
      }
    [] =>
      match value {
        String(s) => Json::string(leaf(s))
        _ => value
      }
    ["*", .. rest] =>
      match value {
        Array(a) => Json::array(a.map(fn(x) { said_stretch(x, rest, leaf~) }))
        Object(m) => {
          let o : Map[String, Json] = Map([])
          for k, v in m {
            o[k] = said_stretch(v, rest, leaf~)
          }
          Json::object(o)
        }
        _ => value
      }
    [k, .. rest] =>
      match value {
        Object(m) =>
          match m.get(k) {
            Some(v) => {
              let o = m.copy()
              o[k] = said_stretch(v, rest, leaf~)
              Json::object(o)
            }
            None => value
          }
        _ => value
      }
  }
}

///|
/// said_paths, each path as its steps.
// kept across runs: said_paths as steps, made once (never changed)
pub let said_steps : Ref[Map[String, Array[Array[String]]]?] = Ref(None)

///|
pub fn said_steps_of(topic : String) -> Array[Array[String]] {
  let all = match said_steps.val {
    Some(m) => m
    None => {
      let m : Map[String, Array[Array[String]]] = Map([])
      for name, paths in said_paths {
        m[name] = paths.map(fn(p) { p.split(".").map(fn(v) { v.to_owned() }).collect() })
      }
      said_steps.val = Some(m)
      m
    }
  }
  all.get(topic).unwrap_or([])
}

///|
/// widest_paths, each path as its steps with the figure at its widest.
// kept across runs: widest_paths as steps, made once (never changed)
let widest_steps : Ref[Map[String, Array[(Array[String], String)]]?] = Ref(None)

///|
fn widest_steps_of(topic : String) -> Array[(Array[String], String)] {
  let all = match widest_steps.val {
    Some(m) => m
    None => {
      let m : Map[String, Array[(Array[String], String)]] = Map([])
      for name, paths in widest_paths {
        m[name] = paths.map(fn(p) { (p.0.split(".").map(fn(v) { v.to_owned() }).collect(), p.1) })
      }
      widest_steps.val = Some(m)
      m
    }
  }
  all.get(topic).unwrap_or([])
}

///|
/// `src` with what people, agents and stations wrote in each topic at its longest (said_paths), and each figure the
/// core writes at its widest (widest_paths: none stays none): the squeeze sweep's stretched pass
/// (squeeze_said_wbtest.mbt), sffix's and sffilm's MBUI_SAID=1 (scripts/squeeze.sh SAID=1).
pub fn said_longest_source(src : Source) -> Source {
  {
    ..src,
    topic_read: fn(name, params) {
      let t = src.topic(name, params).get().snapshot()
      let steps = said_steps_of(name)
      let widest = widest_steps_of(name)
      match t.value {
        Some(v) if steps.length() > 0 || widest.length() > 0 => {
          let mut v = v
          for path in steps {
            v = said_stretch(v, path[:])
          }
          for w in widest {
            v = said_stretch(v, w.0[:], leaf=fn(s) { if s == "" { s } else { w.1 } })
          }
          { ..t, value: Some(v) }
        }
        _ => t
      }
    },
  }
}

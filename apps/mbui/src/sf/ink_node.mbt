// Code in its colours read by a node of the window's tree (ink.mbt's code_ink is the old views'): the same inks the
// core answered, read so that what reads one is told as it is kept or let go, by its code and language alone; the core
// asked as a node's reaction (code_ink_node), never as a binding runs.

///|
/// What a node read of each code's ink, by its key (ink.mbt's `inks`'): told as that one is kept or let go, made as one
/// is first read so, let go as one is told and nothing reads it any more. The old views' read (code_ink) tracks nothing,
/// so none is made for it.
// kept across runs: emptied as the app begins anew (its init)
let inks_told : Map[String, @signals.Signal[Int]] = Map([])

///|
fn init {
  @ui.on_reset(fn() { inks_told.clear() })
}

///|
/// What a node read of the ink of `key` changed (kept, or let go to keep the inks within their budget): told, where one
/// reads it; let go where none does any more.
fn ink_tell(key : String) -> Unit {
  match inks_told.get(key) {
    Some(s) =>
      if s.watched() {
        s.set(s.untracked() + 1)
      } else {
        inks_told.remove(key)
      }
    None => ()
  }
}

///|
/// What each piece of `code` in `lang` is (code_ink's), read by a node: told as it is kept or let go. None while it is
/// not here (code_ink_ask asks it); Some(None) for code shown as it is, and where there is no core to ask. Asks nothing.
pub fn code_ink_told(code : String, lang : String) -> String?? {
  let key = lang + "\u{1}" + code
  let s = match inks_told.get(key) {
    Some(s) => s
    None => {
      let s = @signals.signal(0)
      inks_told[key] = s
      s
    }
  }
  s.get() |> ignore
  match inks.get(key) {
    Some(ink) => Some(ink)
    None => if ink_read.val is None && kept_call.val is None { Some(None) } else { None }
  }
}

///|
/// The core asked once what each piece of `code` in `lang` is (code_ink's ask), unless it is here or asked: what reads
/// it told as it is kept (code_ink_told). Done as something happens (a handler, a node's reaction), never as a binding
/// runs: what is kept at once (a run without a core, its answers kept) tells as it is kept.
pub fn code_ink_ask(code : String, lang : String) -> Unit {
  let key = lang + "\u{1}" + code
  guard !inks.contains(key) else { return }
  match (ink_read.val, kept_call.val) {
    (Some(read), _) =>
      if !inks_asked.contains(key) {
        inks_asked[key] = true
        read(code, lang, fn(ink) { ink_keep(key, ink) })
      }
    (None, Some(kept)) => {
      let ink = match kept("code.ink", { "code": Json::string(code), "lang": Json::string(lang) }, None) {
        Some(Ok((Object(m), _))) =>
          match m.get("ink") {
            Some(String(s)) => Some(s)
            _ => None
          }
        _ => None
      }
      ink_keep(key, ink)
    }
    (None, None) => ()
  }
}

///|
/// What each piece of `code` in `lang` is (as they change) for node `v` to draw by: read as code_ink_told reads it, the
/// core asked as it is not here (as `v` is made, as the code or its language changes, as it is let go to keep the inks
/// within their budget). In `v`'s bones, made-up code: shown as it is, nothing asked (code_ink's in_bones).
pub fn code_ink_node(v : @view.View, code : () -> String, lang : () -> String) -> () -> String?? {
  v.reacts(
    fn() {
      let c = code()
      let l = lang()
      (c, l, code_ink_told(c, l) is None)
    },
    fn(r) {
      if r.2 && !v.in_bones() {
        code_ink_ask(r.0, r.1)
      }
    },
  )
  fn() { if v.in_bones() { Some(None) } else { code_ink_told(code(), lang()) } }
}

// The model control as nodes of the window's tree. Its pick and the work saving it are followed; the panel remains the
// shared presenter in model_triple.mbt, anchored to the actual control node.

///|
/// An owner that outlives a control when a page replaces it at a layout breakpoint. A page can share one between its
/// narrow and wide controls; otherwise the control's parent owns it. The presenter supplies the reanchoring action.
pub struct ModelTripleOwner {
  shown : Ref[Int]
  opened_for : Ref[String]
  anchor : Ref[@view.View?]
  reanchor : Ref[(@view.View) -> Unit]
}

///|
/// Create the owner at a node that survives the page's layout changes, and lend it to that node's descendants.
pub fn model_triple_owner(parent : @view.View) -> ModelTripleOwner {
  let owner : ModelTripleOwner = {
    shown: Ref(0),
    opened_for: Ref(""),
    anchor: Ref(None),
    reanchor: Ref(fn(_) {  }),
  }
  parent.lends(model_triple_owner_lent, owner).owns(fn() { owner.close() }) |> ignore
  owner
}

///|
// kept across runs: an owner is lent by each window, not shared between windows
let model_triple_owner_lent : @view.Lent[ModelTripleOwner] = @view.Lent::new()

///|
/// The closest owner lent by the page's window, if it has one.
pub fn model_triple_owner_at(node : @view.View) -> ModelTripleOwner? {
  node.lent(model_triple_owner_lent)
}

///|
/// Close the owner's panel when its page is actually left or its pick's identity changes.
pub fn ModelTripleOwner::close(owner : ModelTripleOwner) -> Unit {
  let serial = owner.shown.val
  if serial != 0 {
    if @sf.presented_open_of(serial) { @sf.close_presented_of(serial) }
    if triple.shown == serial { triple.open.set("") }
    owner.shown.val = 0
    owner.opened_for.val = ""
    owner.reanchor.val = fn(_) {  }
  }
}

///|
/// The control for the pick of `of` on `station`. It is absent until the pick is read, as the old view's is.
/// `page` supplies a page's own live pick instead of reading the topic; `small` and `floating` select the composer's
/// row and glass-capsule appearances. `saved_live` supplies the current toast when it can change, such as with the
/// language; otherwise `saved` is used. `owner` can be shared across replacement controls on the same page.
pub fn model_triple_node(
  parent : @view.View,
  src : Source,
  station : String,
  of : String,
  saved? : String = "",
  saved_live? : () -> String,
  page? : () -> Json?,
  small? : Bool = false,
  floating? : Bool = false,
  owner? : ModelTripleOwner,
) -> Unit {
  let pick : () -> Json? = match page {
    Some(read) => read
    None => fn() { (src.topic)("pick", pick_params(station, of)).value }
  }
  let saved_at_open : () -> String = match saved_live {
    Some(read) => read
    None => fn() { saved }
  }
  parent.show(fn() { pick() is Some(Object(_)) }, fn(slot) {
    slot.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    let (control, press) = triple_control_node(slot, src, fn() { station }, of, pick, page is Some(_), small, floating,
      fn() { false }, saved_at_open, owner?=owner)
    // A fixture can ask before the pick arrives; take the request when this control can open it.
    control.reacts(fn() { (triple.asked.get(), items(pick(), "options").length() > 0, doing("pick.save/" + station + "/" + of)) }, fn(_) {
      if @signals.untracked(fn() { triple.asked.get() }) == station + "\u{1}" + of {
        if @signals.untracked(fn() { triple.open.get() == station + "\u{1}" + of }) {
          triple.asked.set("")
        } else {
          press()
        }
      }
    })
  })
}

///|
/// The same control for a page that already has its pick (the new chat); `page_pick` also gives the panel its first
/// value. The returned press is used by the new chat's own open request, and belongs to this node's lifetime.
fn triple_control_node(
  parent : @view.View,
  src : Source,
  station : () -> String,
  of : String,
  pick : () -> Json?,
  page_pick : Bool,
  small : Bool,
  floating : Bool,
  going : () -> Bool,
  saved : () -> String,
  owner? : ModelTripleOwner,
) -> (@view.View, () -> Unit) {
  let owner = match owner { Some(shared) => shared; None => model_triple_owner(parent) }
  let me = fn() { station() + "\u{1}" + of }
  let saving = fn() { doing("pick.save/" + station() + "/" + of) }
  let open = fn() { triple.open.get() == me() }
  let value = fn() { field(pick(), "value") }
  let option = fn() { field(pick(), "valueOption") }
  let account = fn() { field(pick(), "account") }
  let runtime = fn() { text(value(), "runtime") }
  let available = fn() { items(pick(), "options").length() > 0 }
  let can = fn() { available() && !saving() && !going() }
  let name = fn() {
    let model = text(value(), "model")
    if model == "" {
      @sf.t("web-main.model.pick")
    } else {
      match text(option(), "name") {
        "" => model
        n => n
      }
    }
  }
  let effort = fn() {
    let e = text(value(), "effort")
    if e == "" { @sf.t("web-main.model.defaultEffort") } else { effort_text(e) }
  }
  let has_runtime = fn() { !flag(pick(), "runtimeFixed") && items(option(), "runtimes").length() > 1 }
  let has_effort = fn() { text(value(), "effort") != "" || items(pick(), "efforts").length() > 0 }
  let profile = fn() { field(account(), "profile") }
  let marked = fn() { profile() is Some(Object(_)) }
  let label = fn() {
    if !available() {
      @sf.t("web-main.model.none")
    } else {
      let parts = [name()]
      if has_runtime() { parts.push(@settings.runtime_label(runtime())) }
      if has_effort() { parts.push(effort()) }
      if text(pick(), "fastText") != "" { parts.push(text(pick(), "fastText")) }
      if text(account(), "text") != "" { parts.push(text(account(), "text")) }
      parts.join(" · ")
    }
  }
  let words = fn() { if small { triple_words_xs } else { triple_words } }
  let muted = fn() { if small { triple_muted_xs } else { triple_muted } }
  let at : Ref[@view.View?] = Ref(None)
  let press = fn() {
    if can() {
      if open() {
        @sf.close_presented_of(triple.shown)
        return
      }
      match at.val {
        Some(control) => {
          triple.asked.set("")
          open_triple_panel(
            src, station(), of, @sf.beside_node(control).anchor(), saved=saved(),
            page=if page_pick { pick() } else { None },
          )
          owner.shown.val = @sf.last_presented()
          owner.opened_for.val = me()
        }
        None => ()
      }
    }
  }
  let control = parent.box(fn(b) {
    let inset = if floating { 12.0 } else if small { 8.0 } else { 10.0 }
    b.row(Is(true)).height(Is(Some(if floating { 30.0 } else { 28.0 })))
    .padding(Is((inset, 0.0, inset, 0.0)))
    .gap(Is(6.0)).lines_up(Is(Some(Middle))).shrink(Is(1.0)).min_width(Is(Some(0.0))).fits(Is(true))
    .radius(By(fn() { if floating { 15.0 } else if small { @ui.tree_theme().corner(Lg) } else { 14.0 } }))
    .glass(By(fn() { if floating { Some(@sf.glass_floating()) } else { None } }))
    .ground(By(fn() { if !floating && (open() || @sf.lit_node(b)) { @sf.theme().p.hover } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    |> ignore
    @sf.presses_node(b, press, on=can)
    b.show(fn() { !available() }, fn(n) {
      triple_node_words(n, fn() { @sf.t("web-main.model.none") }, muted)
    })
    b.show(available, fn(m) {
      @sf.maker_mark_node(m, fn() { text(field(option(), "maker"), "id") }, runtime, 14.0) |> ignore
    })
    b.show(available, fn(n) {
      let style = fn() { if small { triple_name_xs } else { triple_name } }
      n.words(By(name)).words_look(By(fn() { @ui.style_words(style()) }))
      .ink(By(fn() { @ui.style_ink(style()) })).cuts(Is(true), keep=true)
      .min_width(Is(Some(0.0))).allow_ellipsis(Is(true)) |> ignore
    })
    b.show(fn() { available() && has_runtime() }, fn(part) {
      triple_node_part(part, triple_drop_runtime)
      triple_node_words(part, fn() { "·" }, muted)
      triple_node_words(part, fn() { @settings.runtime_label(runtime()) }, words)
    })
    b.show(fn() { available() && has_effort() }, fn(part) {
      triple_node_part(part, triple_drop_effort)
      triple_node_words(part, fn() { "·" }, muted)
      triple_node_words(part, effort, words)
    })
    b.show(fn() { available() && text(pick(), "fastText") != "" }, fn(part) {
      triple_node_part(part, triple_drop_effort)
      triple_node_words(part, fn() { "·" }, muted)
      triple_node_words(part, fn() { text(pick(), "fastText") }, words)
    })
    b.show(fn() { available() && marked() }, fn(part) {
      triple_node_part(part, triple_drop_account)
      triple_node_words(part, fn() { "·" }, muted)
      @sf.maker_mark_node(part, fn() { text(profile(), "mark") }, runtime, 14.0) |> ignore
    })
    b.show(fn() { available() && account() is Some(Object(_)) }, fn(part) {
      triple_node_part(part, triple_drop_name)
      part.gap(By(fn() { if marked() { 0.0 } else { 6.0 } })) |> ignore
      part.show(fn() { !marked() }, fn(dot) { triple_node_words(dot, fn() { "·" }, muted) })
      triple_node_words(part, fn() { text(account(), "text") }, fn() {
        match text(account(), "level") {
          "amber" => triple_amber
          "red" => triple_red
          _ => words()
        }
      })
    })
    b.show(fn() { available() && marked() }, fn(part) {
      triple_node_part(part, triple_drop_account)
      @sf.quota_chips_node(part, fn() { field(profile(), "quota") }, small=true)
    })
    b.show(saving, fn(s) { @sf.spinner_node(s, size=12.0) |> ignore })
    b.show(fn() { !saving() }, fn(c) {
      @sf.icon_node(c, "chevron-down", 12.0, By(fn() { @sf.theme().p.muted })) |> ignore
    })
  })
  at.val = Some(control)
  owner.anchor.val = Some(control)
  let key = @signals.untracked(me)
  let serial = owner.shown.val
  if owner.opened_for.val == key && @sf.presented_open_of(serial) {
    // The replacement can be made while a layout change is still being applied. Hand it over only once that
    // change has settled, and only if the same control and presenter still belong to this owner.
    @signals.after_flush(fn() {
      if control.alive() && owner.shown.val == serial && owner.opened_for.val == key &&
        @sf.presented_open_of(serial) {
        match owner.anchor.val {
          Some(current) if @sf.beside_node(current).anchor() == @sf.beside_node(control).anchor() =>
            (owner.reanchor.val)(control)
          _ => ()
        }
      }
    })
  }
  control.reacts(me, fn(key) {
    if owner.opened_for.val != "" && owner.opened_for.val != key { owner.close() }
  })
  control.owns(fn() {
    match owner.anchor.val {
      Some(current) if @sf.beside_node(current).anchor() == @sf.beside_node(control).anchor() => owner.anchor.val = None
      _ => ()
    }
  }) |> ignore
  (control, press)
}

///|
fn triple_node_part(part : @view.View, drop : Int) -> Unit {
  part.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))).drops(Is(drop)) |> ignore
}

///|
fn triple_node_words(parent : @view.View, words : () -> String, style : () -> @ui.TextStyle) -> Unit {
  @sf.words_node(parent, words, style) |> ignore
}

// The notices standing on a chat's composer. Their data is kept by identity while they leave, so an archive,
// connection or cache answer updates the existing notice and never rebuilds the editor under it.

///|
priv struct ComposerNotice {
  kind : Int
  said : String
  detail : String
  session : String
  afresh : Bool
  offline : Bool
  updating : Bool
  thread : Double?
} derive(Eq)

///|
fn composer_notices_node(parent : @view.View, src : Source, r : ChatRef, view : () -> ChatView?) -> @view.View {
  let key = r.station + ":" + r.session
  let items = fn() {
    let all : Array[ComposerNotice] = []
    match view() {
      Some(v) => {
        let make = fn(kind, said, detail, session, afresh) {
          all.push({ kind, said, detail, session, afresh, offline: v.offline, updating: v.updating, thread: v.thread })
        }
        if v.archived { make(0, @sf.t("web-main.archived.sendRestores"), "", "", false) }
        match v.cache_cold {
          Some((session, status, detail, afresh)) if !v.archived => make(1, status, detail, session, afresh)
          _ => ()
        }
        if v.offline {
          make(2, v.offline_note.unwrap_or_else(fn() {
            if r.station_name != "" { @sf.t("web-main.chat.offline.named", args=[("name", r.station_name)]) }
            else { @sf.t("web-main.chat.offline") }
          }), "", "", false)
        }
      }
      None => ()
    }
    all
  }
  let first = Ref(true)
  parent.box(fn(notices) {
    notices.lines_up(Is(Some(Middle))).width_share(Is(1.0)).max_width(By(composer_widest)) |> ignore
    notices.each(items, fn(n) { n.kind }, fn(n, data) {
      let kind = @signals.untracked(fn() { data.get().kind })
      let cached = kind == 1
      let look = @motion.presence_node(n, initial=first.val, enter=@sf.waiting_in, exit=@sf.leave)
      n.alpha(By(fn() { look().alpha })).scale(By(fn() { look().sx }))
      .drawn_off(By(fn() { (look().dx, look().dy) })).hides(By(fn() { n.leaving() })) |> ignore
      let text_line = fn() {
        @sf.theme().t.meta_line * (if cached { @ui.font_scale() } else { 1.0 })
      }
      let extra = fn() {
        let t = @ui.style_words(@sf.theme().t.words)
        let line = (if t.line > 0.0 { t.line } else { t.size * @ui.tree_theme().text_line }) * @ui.font_scale()
        dmax(0.0, (line - @sf.theme().round.side) / 2.0)
      }
      // (how wide a notice of the cache's needs its summary and its choice in one row: as wide as its room is, beside
      // each other, else the choice under the summary; a notice of another kind has them in no row)
      let beside_needs = fn() {
        if !cached { return @double.infinity }
        let across = fn(s, style) { @view.words_measure(s, @ui.style_words(style), 1.0e9).0 }
        let high = dmax(text_line(), 28.0)
        let side = high + 16.0
        let inset = capsule_pad_alone + extra() + (@sf.theme().round.side + 1.0) / 2.0 - side / 2.0
        let summary = across(data.get().said, composer_notice_status) + 8.0 + across(data.get().detail, composer_notice_flow_words)
        let choice = dmax(across(@sf.t("web-main.chat.goOn"), composer_notice_choice_words), across(@sf.t("web-main.chat.afresh"), composer_notice_choice_words)) + 33.0
        side + summary + 12.0 + choice + (side - 28.0) / 2.0 + 2.0 * inset
      }
      n.width_share(Is(1.0)).margin(Is((0.0, 0.0, 0.0, 8.0))) |> ignore
      n.by_room(By(beside_needs), fn(needs, room, _) { needs <= room }, sized=true, fn(held, beside_now) {
      let beside = fn() { beside_now }
      let high = fn() { if beside() { dmax(text_line(), 28.0) } else { text_line() } }
      let side = fn() { high() + 16.0 }
      let inset = fn() { capsule_pad_alone + extra() + (@sf.theme().round.side + 1.0) / 2.0 - side() / 2.0 }
      held.padding(By(fn() { (inset(), 0.0, inset(), 0.0) })) |> ignore
      held.box(fn(card) {
      card.padding(By(fn() { (0.0, 8.0, if beside() { (side() - 28.0) / 2.0 } else { 16.0 }, 8.0) }))
      .gap(Is(4.0)).radius(By(fn() { @ui.tree_theme().corner(@sf.line_capsule_corner(side())) }))
      .glass(By(fn() { Some(@sf.glass_floating()) })) |> ignore
      let mark = fn(p : @view.View) {
        p.box(fn(m) {
          m.width(By(fn() { Some(side()) })).height(By(fn() { Some(high()) }))
          .lies_along(Is(Middle)).lines_up(Is(Some(Middle))) |> ignore
          m.pick(fn() { kind == 2 && data.get().updating }, fn(s, updating) {
            if updating {
              @sf.updating_mark_node(s, 16.0, fn() { @sf.theme().p.muted })
            } else {
              @sf.icon_node(s, if kind == 0 { "archive" } else if kind == 1 { "wait" } else { "unplug" }, 16.0, By(fn() { @sf.theme().p.muted })) |> ignore
            }
          })
        }) |> ignore
      }
      let words = fn(p : @view.View, text : () -> String, style : @ui.TextStyle) {
        p.box(fn(w) {
          w.words(By(text)).words_look(By(fn() { @ui.style_words(style) })).ink(By(fn() { @ui.style_ink(style) })) |> ignore
        })
      }
      if cached {
        let doing = fn() { "session.settings/" + r.station + "/" + data.get().session }
        let disabled = fn() { n.leaving() || src.read_only || data.get().offline || @sfbase.doing(doing()) }
        let open_key = notice_choice_key(key, "wait")
        n.owns(fn() { if composing.cold_open.get() == open_key { composing.cold_open.set("") } }) |> ignore
        card.box(fn(flow) {
          flow.row(By(beside)).gap(By(fn() { if beside() { 12.0 } else { 0.0 } }))
          .lines_up(By(fn() { if beside() { Some(Middle) } else { None } })) |> ignore
          flow.box(fn(title) {
            title.row(Is(true)).grow(By(fn() { if beside() { 1.0 } else { 0.0 } })).shrink(Is(1.0)).min_width(Is(Some(0.0)))
            .lines_up(By(fn() { Some(if beside() { Middle } else { Start }) })) |> ignore
            mark(title)
            title.box(fn(summary) {
              summary.row(Is(true)).gap(Is(8.0)).wraps(Is(Some(4.0))).lines_up(Is(Some(Middle)))
              .shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
              words(summary, fn() { data.get().said }, composer_notice_status).shrink(Is(1.0)) |> ignore
              words(summary, fn() { data.get().detail }, composer_notice_flow_words).shrink(Is(1.0)) |> ignore
            }) |> ignore
          }) |> ignore
          flow.box(fn(choice) {
            choice.row(Is(true)).padding(By(fn() { (if beside() { 0.0 } else { side() - 8.0 }, 0.0, 0.0, 0.0) })) |> ignore
            @sf.chooser_node(choice, fn() { @sf.t(if data.get().afresh { "web-main.chat.afresh" } else { "web-main.chat.goOn" }) },
              fn() { [false, true].map(fn(next) {
                let label = @sf.t(if next { "web-main.chat.afresh" } else { "web-main.chat.goOn" })
                Some(@sf.menu_item_of(label, fn() {
                  if !disabled() && next != data.get().afresh {
                    @sfbase.act(src, label, doing(), "session.settings", { "station": Json::string(r.station),
                      "key": Json::string(data.get().session), "afresh": Json::boolean(next) })
                  }
                }, chosen=next == data.get().afresh, disabled=disabled()))
              }) }, fn() { composing.cold_open.get() == open_key }, fn(open) {
                if open { composing.cold_open.set(open_key) } else if composing.cold_open.get() == open_key { composing.cold_open.set("") }
              }, disabled~, capsule=beside, side=Top) |> ignore
          }) |> ignore
        }) |> ignore
      } else {
        card.box(fn(row) {
          row.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
          mark(row)
          words(row, fn() { data.get().said }, composer_notice_words)
          .grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          if kind == 0 {
            row.box(fn(offer) {
              let busy = fn() { composing.restoring.contains(key) }
              let disabled = fn() { n.leaving() || src.read_only || busy() || data.get().offline }
              offer.padding(Is((12.0, 0.0, 0.0, 0.0))).presses(By(fn() { !disabled() }))
              .on_press(fn() { if !disabled() { restore_from_composer(src, r, data.get().thread) } })
              .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.archived.restore"))) })) |> ignore
              offer.box(fn(w) {
                w.words(By(fn() { @sf.t(if busy() { "web-main.archived.restoring" } else { "web-main.archived.restore" }) }))
                .words_look(By(fn() { @ui.style_words(composer_notice_button) }))
                .ink(By(fn() { if disabled() { @sf.theme().p.muted } else { @sf.theme().p.text } })) |> ignore
              }) |> ignore
            }) |> ignore
          }
        }) |> ignore
        if kind == 0 {
          card.show(fn() { composing.restore_errors.contains(key) }, fn(error) {
            error.padding(By(fn() { (side(), 0.0, 0.0, 0.0) })) |> ignore
            words(error, fn() { composing.restore_errors.get(key).unwrap_or("") }, composer_notice_failed) |> ignore
          })
        }
      }
      }) |> ignore
      }) |> ignore
    }, leave=@sf.leave_ms)
    first.val = false
  })
}

///|
fn restore_from_composer(src : Source, r : ChatRef, thread : Double?) -> Unit {
  let key = r.station + ":" + r.session
  composing.restoring[key] = true
  composing.restore_errors.remove(key)
  let params : Map[String, Json] = { "station": Json::string(r.station), "session": Json::string(r.session), "archived": Json::boolean(false) }
  match thread { Some(th) => params["thread"] = Json::number(th); None => () }
  (src.call)("chat.archive", Json::object(params), fn(res) {
    composing.restoring.remove(key)
    match res {
      Err(e) => { composing.restore_errors[key] = error_words(e); @ui.haptic(Reject) }
      Ok(_) => @ui.haptic(Confirm)
    }
  })
}

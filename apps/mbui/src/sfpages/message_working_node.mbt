// An agent at work, in one line of its chat's list, as nodes of the window's tree (chat_rows.mbt's activity_row,
// work_ring; their styles the same): its picture ringed while it works (eight arcs turning; a still whole ring while
// it waits on what it started), what it does now as the core says (steadied: activity_steady_node.mbt) and how long
// its turn has run; pressed, its history beside the chat; one of several agents, its own stop under the pointer. Not
// here yet: one step's words giving way to the next's glyph by glyph, and the first's coming in so
// (xfer/rd-glyphs-gap.md: the new words take the old's place whole); the card over its picture (P21). The list's, not
// the row's: the line folding to its picture as a message comes out of it, the picture away while its copy flies, the
// ring fading as the row goes.

///|
/// What agent `a` says it does now, as its row reads it (activity_row's `said`): what it waits on (important: a wait
/// is read), else what the core's `live` says it does (`now`), else that it is at work.
fn working_said(a : Agent, live : Json?) -> ActivitySaid {
  match a.wait {
    Some((_, _, w)) =>
      { key: "wait", words: if w != "" { w } else { @sf.t("web-main.activity.waiting") }, mono: false, important: true }
    None => {
      let n = field(field(live, "activity"), "now")
      match text(n, "text") {
        "" => { key: "busy", words: @sf.t("web-main.activity.busy"), mono: false, important: false }
        s => { key: text(n, "key"), words: s, mono: flag(n, "mono"), important: flag(n, "important") }
      }
    }
  }
}

///|
/// How long agent `a`'s turn has run is worked out from (activity_row's clock): when it began waiting and how long it
/// waits at most (seconds), or when its turn began; None, no clock.
fn working_clock_from(a : Agent) -> (Double, Double?)? {
  match a.wait {
    Some((since, most, _)) => Some((since, most))
    None => a.since.map(fn(s) { (s, None) })
  }
}

///|
/// The clock's words at the core's moment `now` from `since`, no further than `most` seconds after it (then said
/// against it: 1m 5s / 5m).
fn working_clock_words(since : Double, most : Double?, now : Double) -> String {
  match most {
    Some(sec) => {
      let waited = dmin(now, since + sec * 1000.0)
      elapsed(waited - since) + " / " + elapsed(sec * 1000.0)
    }
    None => elapsed(now - since)
  }
}

///|
/// Agent `a` at work (activity_row's, as nodes), as it says as it changes, in its row's room (message_row_frame_node:
/// `key`, its list's Entry::id `act:<agent>`; `side`, `top`; `over`): its picture ringed, what it does now steadied by
/// its key in `steadies` (the row come into its list at `came`, None: there as the chat opened), its clock from then
/// (seen from `came` over row_size_ms); the line pressed opens its history beside the chat; where the chat has more
/// than one agent, its stop under the pointer (session.stop). Read out as who and what it does.
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn working_said_node(
  v : @view.View,
  src : Source,
  here : MessageNodeHere,
  key : String,
  side : () -> Double,
  top : () -> Double,
  a : () -> Agent,
  came : () -> Double?,
  steadies : ActivitySteadies,
  over? : (@view.View, String) -> Unit = fn(_, _) {  },
) -> MessageRowNode {
  let live = fn() {
    @sfbase.hold(src, @sfbase.chat_scope(here.station, here.session), "live", {
      "station": Json::string(here.station),
      "key": Json::string(a().key),
    }).get().value
  }
  let said = fn() { working_said(a(), live()) }
  message_row_frame_node(v, key, side, top, over~, fn(r) {
    r.box(fn(area) {
      @sf.style_node(area, fn() { activity_row_box })
      let _ = area.box(fn(line) {
        @sf.style_node(line, fn() { if message_inline(here) { activity_line_narrow } else { activity_line } })
        line.says(By(fn() { Some(@view.said(Button, label=a().who + "：" + said().words)) })) |> ignore
        @sf.presses_node(line, fn() {
          open_detail(src, message_node_ref(here), @signals.untracked(a).key)
        })
        line.box(fn(face) {
          @sf.style_node(face, fn() { activity_face })
          face.box(fn(av) { agent_avatar_node(av, fn() { a().maker }, fn() { a().runtime }, fn() { "" }) }) |> ignore
          // (its ring over its picture)
          face.box(fn(ring) {
            ring.over(Is(true)) |> ignore
            @sf.style_node(ring, fn() { ring_room_style })
            ring.pick(fn() { a().wait is Some(_) }, fn(k, waiting) {
              if waiting {
                k.box(fn(w) { @sf.style_node(w, fn() { ring_waiting }) }) |> ignore
              } else {
                @sf.segments_node(k, ring_side, ring_stroke, fn() { @sf.theme().p.accent }, fn() { @sf.theme().p.bg })
                |> ignore
              }
            })
          })
          |> ignore
        })
        |> ignore
        // what it does now, and how long
        line.box(fn(tail) {
          @sf.style_node(tail, fn() { activity_tail }, in_row=true)
          let shown = activity_steady_node(tail, steadies, key, said, came)
          let style = fn() { if @sf.hovered_node(line) { now_words_hot } else { now_words } }
          tail.box(fn(w) {
            w
            .words_runs(By(fn() {
              let s = shown().said
              [@ui.span(s.words, mono=s.mono)]
            }))
            .words_look(By(fn() { @ui.style_words(style()) }))
            .ink(By(fn() { @ui.style_ink(style()) }))
            // (cut short where the line has not the room: now_words' w=Cut)
            .cuts(Is(true))
            .min_width(Is(Some(0.0)))
            .allow_ellipsis(Is(true))
            |> ignore
          })
          |> ignore
          tail.pick(fn() { working_clock_from(a()) }, fn(k, from) {
            match from {
              Some((since, most)) => {
                let tick = steps_seconds(k, src, since, till?=most.map(fn(sec) { sec * 1000.0 }))
                let clock = @sf.words_node(
                  k,
                  fn() {
                    tick() |> ignore
                    working_clock_words(since, most, (src.now)())
                  },
                  fn() { activity_clock },
                )
                // (seen from when the row came into its list, as its rows' size goes)
                let seen = @motion.Way::new(1.0)
                k.reacts(came, fn(at) {
                  match at {
                    Some(at) => {
                      seen.put(0.0)
                      seen.go(1.0, @motion.tween(@ui.row_size_ms, ease=Out), at~)
                    }
                    None => seen.put(1.0)
                  }
                })
                clock.alpha(By(fn() { seen.shown_on(clock) })) |> ignore
              }
              None => ()
            }
          })
        })
        |> ignore
      })
      // one of several agents: stopped alone from its row, under the pointer
      // (a mouse over its line or its stop: an old view's row hovered by any of its parts)
      area.show(fn() { (here.view)().agents.length() > 1 && @sf.lit_in_node(area) }, fn(s) {
        working_stop_node(s, src, here, a)
      })
    })
    |> ignore
  })
}

///|
/// Agent `a`'s stop (activity_row's) in `v`: its icon in the muted ink, the text's and the hover ground under the
/// pointer, its words in its tip; pressed, its turn asked to stop (session.stop). Read out a button.
fn working_stop_node(v : @view.View, src : Source, here : MessageNodeHere, a : () -> Agent) -> Unit {
  let label = fn() { @sf.t("web-main.activity.stop", args=[("who", a().who)]) }
  v.box(fn(b) {
    let hot = fn() { @sf.hovered_node(b) }
    @sf.style_node(b, fn() { if hot() { activity_stop_hot } else { activity_stop } })
    b.says(By(fn() { Some(@view.said(Button, label=label())) })) |> ignore
    @sf.presses_node(b, fn() {
      act(src, @sf.t("web-pages.chat.stop"), "", "session.stop", {
        "station": Json::string(here.station),
        "key": Json::string(@signals.untracked(a).key),
      }, done=@sf.t("web-pages.chat.stopAsked"))
    })
    @sf.icon_node(b, "stop", stop_icon, By(fn() {
      let p = @sf.theme().p
      if hot() {
        p.text
      } else {
        p.muted
      }
    }))
    |> ignore
    @sf.tip_node(here.tips, b, label) |> ignore
  })
  |> ignore
}

///|
/// The ring's room over the picture: all of the face (activity_face's 24).
// kept across runs: a value (no field of it changes)
let ring_room_style : @ui.Style = @ui.css("w=Full h=Full")

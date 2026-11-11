// A station's card over where a chat names it, and its part under an agent's card (station_peek_card,
// station_peek_part), as nodes of the window's tree made once in a hover card (@sf.hover_card_node, `padded` false):
// what they say and how, the same as those; made of the station card's own parts (station_peek_node's: the machine in
// brief, peek_figures_node; where to go on, its screens' and files' items). They read what those read, no more: the
// workspace's stations (its name), the station (what it says of itself, whether it is up), its screens, and how this
// device reaches it (`stationNet`) only while it is up and its machine shows, as peek_figures does.

///|
/// The station card at `address` (`ws/station`) in `v` (station_peek_card's), with the frame's core as it is said
/// (panels_core: none, nothing; another workspace's, made again with that one's): its dot, its mark and its name, what
/// it says of itself and, up, its machine in brief (else why it is down); then where to go on, rows at the card's
/// padding. `stint`: the page's time on top, what its mark's picture is asked for on.
pub fn station_peek_card_node(v : @view.View, address : String, stint : () -> Int) -> Unit {
  peek_with_core(v, fn(b, core) {
    let st = peek_station_topics(core, address)
    let t = fn() { @sf.theme() }
    b.box(fn(card) {
      @sf.style_node(card, fn() { peek_card })
      card.box(fn(w) {
        @sf.style_node(w, fn() { peek_card_words })
        w.box(fn(h) {
          @sf.style_node(h, fn() { peek_card_head })
          // (the same dot as on its tile in the chat's bar: how this device reaches it, not only whether it is up)
          @sf.state_dot_node(h, fn() {
            match station_via((st.s)()) {
              "direct" => "online"
              "relay" => "busy"
              "offline" => "error"
              "waiting" => "waiting"
              _ => "online"
            }
          })
          peek_mark_node(h, st, stint, fn() { t().p.muted })
          @sf.words_node(h, st.name, fn() { peek_card_name }) |> ignore
        })
        |> ignore
        w.show(fn() { (st.s)() is Some(_) }, fn(x) {
          // (what it says and its machine as far apart as the card's words: peek_card_words' gap)
          @sf.style_node(x, fn() { peek_card_said })
          @sf.words_node(x, fn() { text((st.s)(), "summary") }, fn() { peek_said }) |> ignore
          x.pick(fn() { flag((st.s)(), "online") }, fn(y, online) {
            if online {
              peek_figures_by(y, core, st)
            } else {
              @sf.words_node(y, fn() { peek_down((st.s)()) }, fn() { peek_said }) |> ignore
            }
          })
        })
      })
      |> ignore
      peek_ways_node(card, core, address, st)
    })
    |> ignore
  })
}

///|
/// The station card's part under its agent's card in one (station_peek_part's) in `v`: its head as an agent card's (its
/// mark on a square 28 of the neutral ground, or its name's first letter, its name beside it), under it a dot in its
/// tone (up or not) and what it says of itself (down, why); up, its machine at a glance; then where to go on.
pub fn station_peek_part_node(v : @view.View, address : String, stint : () -> Int) -> Unit {
  peek_with_core(v, fn(b, core) {
    let st = peek_station_topics(core, address)
    let online = fn() { flag((st.s)(), "online") }
    b.box(fn(card) {
      @sf.style_node(card, fn() { peek_card })
      card.box(fn(w) {
        @sf.style_node(w, fn() { peek_card_words })
        w.box(fn(h) {
          @sf.style_node(h, fn() { peek_part_head })
          h.box(fn(q) {
            @sf.style_node(q, fn() { peek_part_square.then(@ui.style(radius=@sf.small_radius)) })
            q.pick(fn() { @sf.has_station_mark(text((st.s)(), "emoji"), text((st.s)(), "icon")) }, fn(m, marked) {
              if marked {
                @sf.station_mark_node(m, fn() { text((st.s)(), "emoji") }, fn() { text((st.s)(), "icon") }, peek_card_mark, fn() {
                  @sf.theme().p.text
                }, stint)
              } else {
                // (none of its own: its name's first letter)
                @sf.words_node(
                  m,
                  fn() {
                    let name = (st.name)()
                    if name.length() > 0 {
                      name.clamped_view(end=1).to_owned()
                    } else {
                      ""
                    }
                  },
                  fn() { peek_part_name },
                )
                |> ignore
              }
            })
          })
          |> ignore
          @sf.words_node(h, st.name, fn() { peek_part_name }) |> ignore
        })
        |> ignore
        w.show(fn() { (st.s)() is Some(_) }, fn(x) {
          @sf.style_node(x, fn() { peek_card_said })
          x.box(fn(r) {
            @sf.style_node(r, fn() { peek_part_status })
            r.box(fn(d) {
              @sf.style_node(d, fn() { peek_part_dot_room })
              d.box(fn(dot) {
                @sf.style_node(dot, fn() { peek_part_dot.then(@ui.style(bg=if online() { Positive } else { Subtle })) })
              })
              |> ignore
            })
            |> ignore
            let said = @sf.words_node(r, fn() { if online() { text((st.s)(), "summary") } else { peek_down((st.s)()) } }, fn() {
              peek_part_words
            })
            // (what the dot leaves of the row: peek_part_words' w=Full)
            @sf.style_node(said, fn() { peek_card_said_room }, in_row=true)
          })
          |> ignore
          x.show(online, fn(y) { peek_figures_by(y, core, st) })
        })
      })
      |> ignore
      peek_ways_node(card, core, address, st)
    })
    |> ignore
  })
}

///|
/// What a station's card in a hover card reads, each followed (station_peek_card's): its name as the workspace's
/// stations say it (peek_name's), the station as its own page has it (peek_station's), its screens.
priv struct PeekTopics {
  name : () -> String
  s : () -> Json?
  screens : () -> Json?
}

///|
fn peek_station_topics(core : Core, address : String) -> PeekTopics {
  let stations = (core.topic)("stations", { "scope": str(peek_scope(address)) })
  let station = (core.topic)("station", { "scope": str(workspace_of(address)), "station": str(address) })
  let screens = (core.topic)("screens", { "station": str(address) })
  {
    name: fn() { peek_name_of(stations.get().value, address) },
    s: fn() {
      match station.get().value {
        Some(Object(_)) as s => s
        _ => None
      }
    },
    screens: fn() { screens.get().value },
  }
}

///|
/// `make` in `v` with the frame's core as it is said (open_station_peek's): made with it as one comes, made again with
/// another workspace's as that one is said; none, nothing.
fn peek_with_core(v : @view.View, make : (@view.View, Core) -> Unit) -> Unit {
  v.pick(fn() { panels_core.get().map(fn(p) { p.0 }) }, fn(b, workspace) {
    match (workspace, panels_core_as_is()) {
      (Some(_), Some(core)) => make(b, core)
      _ => ()
    }
  })
}

///|
/// Its mark (16) in `ink` where it has one (station_mark's in the card's head), none where it has none.
fn peek_mark_node(p : @view.View, st : PeekTopics, stint : () -> Int, ink : () -> Int64) -> Unit {
  p.show(fn() { @sf.has_station_mark(text((st.s)(), "emoji"), text((st.s)(), "icon")) }, at_once=true, fn(m) {
    @sf.station_mark_node(m, fn() { text((st.s)(), "emoji") }, fn() { text((st.s)(), "icon") }, peek_card_mark, ink, stint)
  })
}

///|
/// The machine in brief in `p` (peek_figures', as peek_figures_node draws it), how this device reaches it asked of the
/// core here, while it shows (peek_figures' station_net: only while the station is up).
fn peek_figures_by(p : @view.View, core : Core, st : PeekTopics) -> Unit {
  let net = (core.topic)("stationNet", { "station": str(text((st.s)(), "station")) })
  peek_figures_node(p, st.s, fn() { station_net_of(net.get().value) })
}

///|
/// Where to go on from it in `p` (peek_ways', as rows of a small panel): its screens, its files where it has a drive,
/// its page. Pressed, what each opens opened (the card left as it is: peek_ways' close is none).
fn peek_ways_node(p : @view.View, core : Core, address : String, st : PeekTopics) -> Unit {
  let close = fn() {  }
  // (its screens asked while it shows, as peek_ways asks them as it is built: its 屏幕 opens on them)
  p.reacts(fn() { (st.screens)() is Some(_) }, at_start=false, fn(_) {  })
  @sf.submenu_row_node(p, fn() { tr("android-misc.screen.section") }, fn() {
    peek_screen_items(core, address, (st.screens)(), close)
  })
  p.show(fn() { field(field((st.s)(), "overview"), "drive") is Some(Object(_)) }, fn(d) {
    @sf.submenu_row_node(d, fn() { tr("android-misc.drive.title") }, fn() {
      peek_file_items(core, address, field(field((st.s)(), "overview"), "drive"), close)
    })
  })
  @sf.panel_row_node(p, fn() { tr("android-chat.station.details") }, fn() { (core.push)(Station(address)) }, end="panel-open", plain=true)
}

///|
/// What it says and its machine under it, as far apart as the card's words (peek_card_words' gap).
// kept across runs: a value (no field of it changes)
let peek_card_said : @ui.Style = @ui.css("w=Full gap=S2")

///|
/// What a station's part says: what its dot leaves of the row (peek_part_words' w=Full).
// kept across runs: a value (no field of it changes)
let peek_card_said_room : @ui.Style = @ui.css("w=Full")
